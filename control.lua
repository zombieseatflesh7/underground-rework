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

  local is_ghost
  if underground_name == "entity-ghost" and entity.ghost_type == "underground-belt" then
    is_ghost = true
    underground_name = entity.ghost_name
  elseif not (entity.type == "underground-belt") then
    return
  end
  -- entity is an underground belt or a ghost of one
  
  local belt_name = transport_belts[underground_name] --related transport belt prototype
  local neighbour = entity.neighbours --connected underground
  
  if neighbour then
    local neighbour_is_ghost = neighbour.name == "entity-ghost"
    -- TODO check for existing connection

    -- on new connection
    local connection = {} --{input, output, name, length, container}
    storage.belt_pairs[pos_string(entity.position)] = connection
    storage.belt_pairs[pos_string(neighbour.position)] = connection
    game.print(event.tick.." new connection from "..pos_string(entity.position).." to "..pos_string(neighbour.position))
    
    connection[entity.belt_to_ground_type] = entity
    connection[neighbour.belt_to_ground_type] = neighbour
    connection.name = underground_name
    local length = get_underground_distance(entity.position, neighbour.position)
    connection.length = length
    
    -- take items from player if placed by hand
    local count = 0
    if not is_ghost and not neighbour_is_ghost then
      local player = game.get_player(event.player_index)
      if player then
        count = player.remove_item{name=belt_name, count=length}
        if count > 0 then
          player.create_local_flying_text{
            text = {"", -count, " ", prototypes.item[belt_name].localised_name}, -- TODO icon in text
            position = {entity.position.x + 1, entity.position.y - 0.5}
          }
        end
        if count ~= length then
          player.clear_cursor() --this prevents weird auto-placements
        end
      end
    end

    if count ~= length then
      -- create storage container
      local container = entity.surface.create_entity{
        name = underground_name.."-container",
        position = connection.input.position,
        force = entity.force,
        spill = false
      }
      connection.container = container

      -- stop the underground if placed by player who doesn't have enough transport belts
      if not is_ghost and not neighbour_is_ghost then
        connection.input = stop_belt(connection.input)
        connection.output = stop_belt(connection.output)
        storage.belt_pairs_ticking[pos_string(container.position)] = connection
      end

      if count > 0 then
        container.get_inventory(defines.inventory.chest).insert({name=belt_name, count=count})
      end
      if (count < length) then
        make_request(container, belt_name, length - count)
      end
    end
  end
end)

function new_connection(connection)
  
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

    if entity.name ~= "entity-ghost" then --destroy the belt immediately
      local name = entity.name
      if stopped then
        name = string.sub(name, 1, name:len()-8)
      end
      event.buffer.insert{name=name, count=1} 
      entity.destroy()
    end
  end

  if itemstack then
    event.buffer.insert(itemstack)
  end

  if stopped then
    neighbour = start_belt(neighbour)
  end

  -- TODO check neighbour for new connections
  local new_neighbour = neighbour.neighbours
  if new_neighbour then
    game.print(event.tick.." new connection from "..pos_string(neighbour.position).." to "..pos_string(new_neighbour.position))
  end
end)

script.on_event(defines.events.on_robot_mined_entity, function(event)
  --underground_removed(event.entity, event.buffer)
end)

function underground_removed(entity, buffer)
  
end

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