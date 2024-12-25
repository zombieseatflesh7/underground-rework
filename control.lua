script.on_init(function()
  storage.belt_pairs = {}
  storage.belt_pairs_ticking = {}
end)

--[[ belt_pairs
key: coordinates
value: input, output, name, length, container, request
]]

-- a table of underground belts to their respective transport belt
local belt_names = {}
belt_names["underground-belt"] = "transport-belt"
belt_names["fast-underground-belt"] = "fast-transport-belt"
belt_names["express-underground-belt"] = "express-transport-belt"

function fix_storage()
  
end

-- TODO rewrite
script.on_nth_tick(12, function()
  for key, connection in pairs(storage.belt_pairs_ticking) do
    local itemstack = connection.container.get_inventory(defines.inventory.chest).get_contents()[1]
    if itemstack and itemstack.name == belt_names[connection.name] and itemstack.count == connection.length then
      connection.container.destroy()
      connection.container = nil
      connection.request = nil
      -- TODO: handle broken connections as a result of restarting belts
      connection.input = start_belt(connection.input)
      connection.output = start_belt(connection.output)
      storage.belt_pairs_ticking[key] = nil
    else
      make_request_proxy(connection)
    end
  end
end)

function update_underground(pos)
  
end

-- handle player placing underground belts + ghosts
script.on_event(defines.events.on_built_entity, function(event) 
  --game.print("on built entity")
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
    -- check for existing connection
    local itemstack
    local neighbour_connection = storage.belt_pairs[pos_string(neighbour.position)]
    if neighbour_connection then
      if neighbour_connection[entity.belt_to_ground_type] == entity then
        return --duplicate connection
      else
        itemstack = break_connection(neighbour_connection)
      end
    end

    local player
    if entity.type ~= "entity-ghost" then
      player = game.get_player(event.player_index)
    end

    itemstack = new_connection(player, entity, neighbour, underground_name, itemstack)

    if itemstack and player then
      player.insert(itemstack) -- does not show text / does not handle full inventory
    end
  end
end)

function new_connection(player, entity, neighbour, underground_name, itemstack)
  game.print("new connection from "..pos_string(entity.position).." to "..pos_string(neighbour.position))

  local belt_name = belt_names[underground_name] --related transport belt prototype

  local entity_is_ghost = entity.name == "entity-ghost"
  local neighbour_is_ghost = neighbour.name == "entity-ghost"

  local connection = {} --{input, output, name, length, container}
  storage.belt_pairs[pos_string(entity.position)] = connection
  storage.belt_pairs[pos_string(neighbour.position)] = connection
  
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

      if belts > 0 then
        itemstack = {name=belt_name, count=belts}
      end

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
    local container = spawn_container(connection.input)
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

    if (belts ~= length) then
      make_request_proxy(connection)
    end
  end

  return trashstack
end

function break_connection(connection)
  game.print("breaking connection between "..pos_string(connection.input.position).." and "..pos_string(connection.output.position))

  --clear storage values
  if storage.belt_pairs_ticking[pos_string(connection.input.position)] then
    storage.belt_pairs_ticking[pos_string(connection.input.position)] = nil
    -- TODO: handle broken connections as a result of restarting belts
    connection.input = start_belt(connection.input)
    connection.output = start_belt(connection.output)
  end
  storage.belt_pairs[pos_string(connection.input.position)] = nil
  storage.belt_pairs[pos_string(connection.output.position)] = nil

  --return connection contents
  local container = connection.container
  local itemstack

  if container then 
    itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
    container.destroy()
  elseif connection.input.name == connection.name and connection.output.name == connection.name then
    itemstack = {name=belt_names[connection.name], count=connection.length}
  end

  return itemstack
end

-- when robots builds undergrounds, i check if it still needs transport belts or not
script.on_event(defines.events.on_robot_built_entity, function(event)
  --game.print("on robot built entity")
  local entity = event.entity
  if not (entity.type == "underground-belt") then return end

  local connection = storage.belt_pairs[pos_string(entity.position)]
  if (not connection) or (not connection.container) then return end
  -- we can assume that there are 2 connected undergrounds and that container is valid

  -- update the connection
  connection[entity.belt_to_ground_type] = entity
  local neighbour = connection.input
  if entity.belt_to_ground_type == "input" then
    neighbour = connection.output
    upgrade_container(connection)
  end
  if (not neighbour.valid) and entity.neighbours then -- neighbour was upgraded
    --game.print("neighbour upgraded")
    neighbour = entity.neighbours
    connection[neighbour.belt_to_ground_type] = neighbour
    if neighbour.belt_to_ground_type == "input" then
      upgrade_container(connection)
    end
  end
  
  if entity.name == connection.name and neighbour.name == connection.name then
    local itemstack = connection.container.get_inventory(defines.inventory.chest).get_contents()[1]
    -- has the required transport belts
    if itemstack and itemstack.name == belt_names[connection.name] and itemstack.count == connection.length then
      connection.container.destroy() -- TODO refactor this for new health system
      connection.container = nil
      connection.request = nil
    else
      connection.input = stop_belt(connection.input)
      connection.output = stop_belt(connection.output)
      storage.belt_pairs_ticking[pos_string(connection.container.position)] = connection
    end
  end
end)

-- handle player mining things
script.on_event(defines.events.on_player_mined_entity, function(event)
  --game.print("on player mined entity")
  local entity = event.entity
  local neighbour

  local connection = storage.belt_pairs[pos_string(entity.position)]
  if not connection then return end
  if not (entity == connection.input or entity == connection.output or entity == connection.container) then return end
  --mined entity is part of an underground connection
  if not (connection.input.valid and connection.output.valid) then return end

  local player
    if entity.type ~= "entity-ghost" then
      player = game.get_player(event.player_index)
    end

  --destroy connection
  game.print("Destroying connection between "..pos_string(connection.input.position).." and "..pos_string(connection.output.position))
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
      container.destroy()
      connection.container = nil
      connection.request = nil
    elseif connection.input.name == connection.name and connection.output.name == connection.name then
      itemstack = {name=belt_names[connection.name], count=connection.length}
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

-- upgrading ghosts
-- TODO handle downgrades which break belt connections
script.on_event(defines.events.on_pre_ghost_upgraded, function(event)
  if event.target.type ~= "underground-belt" then return end

  local connection = storage.belt_pairs[pos_string(event.ghost.position)]
  local underground_name = event.target.name
  if (not connection) or (connection.name == underground_name) then return end
  -- TODO check for upgraded ghosts on the input side, even if the connection has already been upgraded (mixed connection)
  -- upgrade the container with the ghost

  connection.name = underground_name
  upgrade_container(connection)
end)

-- TODO merge with above
script.on_event(defines.events.on_marked_for_upgrade, function(event)
  if event.target.type ~= "underground-belt" then return end

  local connection = storage.belt_pairs[pos_string(event.entity.position)]
  local underground_name = event.target.name
  if (not connection) or (connection.name == underground_name) then return end

  connection.name = underground_name
  clear_request(connection)
  if not connection.container then -- create container
    connection.container = spawn_container(connection.input)
    connection.container.insert{name=belt_names[event.entity.name], count=connection.length}
    
    -- stop the underground 
    if connection.input ~= "entity-ghost" and connection.output ~= "entity-ghost" then
      connection.input = stop_belt(connection.input)
      connection.input.order_upgrade{target=underground_name, force=connection.input.force, player=game.get_player(event.player_index)}
      connection.output = stop_belt(connection.output)
      connection.output.order_upgrade{target=underground_name, force=connection.output.force, player=game.get_player(event.player_index)}
      
      --storage.belt_pairs_ticking[pos_string(container.position)] = connection
    end
  end

  make_request_proxy(connection)
end)

script.on_event(defines.events.on_robot_mined_entity, function(event)
  --underground_removed(event.entity, event.buffer)
end)

function pos_string(pos)
  return pos.x.." "..pos.y
end

function get_underground_distance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

function spawn_container(entity)
  local underground_name = entity.name
  if entity.name == "entity-ghost" then
    underground_name = entity.ghost_name
  end
  local container = entity.surface.create_entity{
    name = underground_name.."-container",
    position = entity.position,
    force = entity.force,
    spill = false
  }
  container.destructible = false -- TODO overhaul this
  return container
end

function upgrade_container(connection)
  if connection.container.name == connection.name.."-container" then return end
  local entity = connection.input
  local container = entity.surface.create_entity{
    name = connection.name.."-container",
    position = entity.position,
    force = entity.force,
    fast_replace = true,
    spill = false
  }
  container.destructible = false -- TODO overhaul this
  connection.container = container
  clear_request(connection)
  make_request_proxy(connection)
end

function make_request_proxy(connection)
  local container = connection.container
  local request = connection.request
  local item = belt_names[connection.name]
  local amount = connection.length
  local itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
  local insert_plan = {}
  local removal_plan = {}

  if itemstack then
    if itemstack.name == item then
      amount = amount - itemstack.count
    else
      removal_plan = make_insert_plan(itemstack.name, itemstack.count)
    end
  end

  if amount == 0 then 
    return nil
  elseif amount > 0 then
    insert_plan = make_insert_plan(item, amount)
  else -- amount < 0
    removal_plan = make_insert_plan(item, math.abs(amount))
  end

  if request and request.valid and request.proxy_target == container then
    request.insert_plan = insert_plan
    request.removal_plan = removal_plan
  else
    connection.request = container.surface.create_entity{
      name = "item-request-proxy",
      position = container.position,
      force = container.force,
      target = container,
      modules = insert_plan,
      removal_plan = removal_plan
    }
  end
end

function make_insert_plan(item, amount)
  return {{
    id = {name = item},
    items = {in_inventory = {
      {
        inventory = defines.inventory.chest,
        stack = 0,
        count = amount
      }
    }}
  }}
end

function clear_request(connection)
  local request = connection.request
  if request and request.valid then
    request.insert_plan = {}
    request.removal_plan = {}
    connection.request = nil
  end
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