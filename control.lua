script.on_init(function()
  storage.belt_pairs = {}
  storage.belt_pairs_ticking = {}
end)

--[[ belt_pairs
key: coordinates
value: input, output, name, length, container
]]

-- a table of underground belts to their respective transport belt
local transport_belts = {}
transport_belts["underground-belt"] = "transport-belt"
transport_belts["fast-underground-belt"] = "fast-transport-belt"
transport_belts["express-underground-belt"] = "express-transport-belt"

function fix_storage()
  
end

-- TODO rewrite
script.on_nth_tick(1, function()
  for key, connection in pairs(storage.belt_pairs_ticking) do
    local container = connection.container
    local itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
    if itemstack and itemstack.name == transport_belts[connection.name] and itemstack.count == connection.length then
      connection.container.destroy()
      connection.container = nil
      connection.input = start_belt(connection.input)
      connection.output = start_belt(connection.output)
      storage.belt_pairs_ticking[key] = nil
    end
  end
end)

function update_underground(pos)
  
end

-- handle player placing underground belts + ghosts
script.on_event(defines.events.on_built_entity, function(event) 
  local entity = event.entity
  local underground_name = entity.name --prototype name

  if underground_name == "entity-ghost" and entity.ghost_type == "underground-belt" then
    underground_name = entity.ghost_name
  elseif not (entity.type == "underground-belt") then
    return
  end
  -- entity is an underground belt or a ghost of one
  
  local neighbour = entity.neighbours --connected underground
  if neighbour then
    local player
    if entity.type ~= "entity_ghost" then
      player = game.get_player(event.player_index)
    end

    -- TODO check for existing connection

    new_connection(player, entity, neighbour, underground_name)
  end
end)

function new_connection(player, entity, neighbour, underground_name, itemstack)
  local belt_name = transport_belts[underground_name] --related transport belt prototype

  local entity_is_ghost = entity.name == "entity-ghost"
  local neighbour_is_ghost = neighbour.name == "entity-ghost"

  -- on new connection
  local connection = {} --{input, output, name, length, container}
  storage.belt_pairs[pos_string(entity.position)] = connection
  storage.belt_pairs[pos_string(neighbour.position)] = connection
  game.print("new connection from "..pos_string(entity.position).." to "..pos_string(neighbour.position))
  
  connection[entity.belt_to_ground_type] = entity
  connection[neighbour.belt_to_ground_type] = neighbour
  connection.name = underground_name
  local length = get_underground_distance(entity.position, neighbour.position)
  connection.length = length
  
  local belts = 0
  local trashstack
  if itemstack and itemstack.name == belt_name then
    belts = itemstack.count
  end

  -- manual placement logic
  if player then
    if itemstack and itemstack.name ~= belt_name then --refund irrelevant belts to the player
      trashstack = itemstack
      itemstack = nil
    end

    if belts < length then --take belts from the player
      local count = player.remove_item{name=belt_name, count=length-belts}
      belts = belts + count
      itemstack = {name=belt_name, count=belts}

      if count > 0 then --floating text
        player.create_local_flying_text{
          text = {"", -count, " ", prototypes.item[belt_name].localised_name}, -- TODO icon in text
          position = {entity.position.x + 1, entity.position.y - 0.5}
        }
      end
      
      if belts < length then
        player.clear_cursor() --clear the cursor if you run out of belts. this prevents weird auto-placements
      end

    elseif belts > length then --refund excess belts to the player
      itemstack.count = belts - length
      trashstack = itemstack
      itemstack = nil
      belts = length
    end
  end

  if entity_is_ghost or neighbour_is_ghost or belts ~= length then
    -- create storage container
    local container = entity.surface.create_entity{
      name = underground_name.."-container",
      position = connection.input.position,
      force = entity.force,
      spill = false
    }
    connection.container = container

    -- stop the underground if placed by player who doesn't have enough transport belts
    if not entity_is_ghost and not neighbour_is_ghost then
      connection.input = stop_belt(connection.input)
      connection.output = stop_belt(connection.output)
      storage.belt_pairs_ticking[pos_string(container.position)] = connection
    end

    if itemstack then
      container.get_inventory(defines.inventory.chest).insert(itemstack)
    end

    if (belts < length) then
      make_request(container, belt_name, length - belts) -- TODO fix this
    end
  end

  return trashstack
end

-- when robots builds undergrounds, i check if it still needs transport belts or not
script.on_event(defines.events.on_robot_built_entity, function(event)
  local entity = event.entity
  if not (entity.type == "underground-belt") then return end

  local connection = storage.belt_pairs[pos_string(entity.position)]
  if not connection then return end
  connection[entity.belt_to_ground_type] = entity

  -- underground belts are valid
  if connection.input.name == connection.name and connection.output.name == connection.name then
    local container = connection.container
    local itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
    -- has the required transport belts
    if itemstack and itemstack.name == transport_belts[connection.name] and itemstack.count == connection.length then
      connection.container.destroy()
      connection.container = nil
    else
      connection.input = stop_belt(connection.input)
      connection.output = stop_belt(connection.output)
      storage.belt_pairs_ticking[pos_string(container.position)] = connection
    end
  end
end)

function pos_string(pos)
  return pos.x.." "..pos.y
end

function get_underground_distance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- handle player mining things
script.on_event(defines.events.on_player_mined_entity, function(event)
  local entity = event.entity
  local neighbour

  local connection = storage.belt_pairs[pos_string(entity.position)]
  if not connection then return end
  if not (entity == connection.input or entity == connection.output or entity == connection.container) then return end
  --mined entity is part of an underground connection

  --destroy connection
  local stopped = false
  if storage.belt_pairs_ticking[pos_string(connection.input.position)] then
    storage.belt_pairs_ticking[pos_string(connection.input.position)] = nil
    stopped = true
  end
  storage.belt_pairs[pos_string(connection.input.position)] = nil
  storage.belt_pairs[pos_string(connection.output.position)] = nil

  --cleanup
  local container = connection.container
  local itemstack

  if entity == container then --mine the container
    neighbour = connection.output
    connection.input.destroy()
  else
    neighbour = entity.neighbours

    if container then --return connection contents
      itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
    elseif connection.input.name == connection.name and connection.output.name == connection.name then
      itemstack = {name=transport_belts[connection.name], count=connection.length}
    end
    -- TODO handle full inventory

    entity.destroy()
  end

  if stopped then
    neighbour = start_belt(neighbour)
  end

  -- check neighbour for new connections
  local new_neighbour = neighbour.neighbours
  if new_neighbour then
    itemstack = new_connection(game.get_player(event.player_index), neighbour, new_neighbour, connection.name, itemstack)
  end

  if itemstack then
    event.buffer.insert(itemstack)
  end
end)

function destroy_connection(connection)

end

script.on_event(defines.events.on_robot_mined_entity, function(event)
  --underground_removed(event.entity, event.buffer)
end)

function stop_belt(entity)
  entity = entity.surface.create_entity{
    name = entity.name.."-stopped",
    position = entity.position,
    force = entity.force,
    direction = entity.direction,
    type = entity.belt_to_ground_type,
    fast_replace = true,
    spill = false
  }
  -- TODO add custom status 
  return entity
end

function start_belt(entity)
  return entity.surface.create_entity{
    name = string.sub(entity.name, 1, entity.name:len()-8),
    position = entity.position,
    force = entity.force,
    direction = entity.direction,
    type = entity.belt_to_ground_type,
    fast_replace = true,
    spill = false
  }
end

function make_request(container, item, amount)
  container.surface.create_entity{
    name = "item-request-proxy",
    position = container.position,
    force = container.force,
    target = container,
    modules = {{
        id = {name = item},
        items = {in_inventory = {
          {
            inventory = defines.inventory.chest,
            stack = 0,
            count = amount
          }
        }}
      }}
    }
end