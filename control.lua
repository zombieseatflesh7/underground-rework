script.on_init(function()
  storage.belt_pairs = {}
  storage.belt_pairs_ticking = {}
  storage.belt_orphans = {}
  storage.belt_orphans_ticking = {}
end)

--[[ belt_pairs
key: coordinate string
value: input, output, name, length, container, request

-- belt_orphans 
key: coordinate string
value: belt, container, request
]]

-- a table of underground belts to their respective transport belt
local belt_names = {}
belt_names["underground-belt"] = "transport-belt"
belt_names["fast-underground-belt"] = "fast-transport-belt"
belt_names["express-underground-belt"] = "express-transport-belt"

local container_names = {}
container_names["underground-belt-container"] = true
container_names["fast-underground-belt-container"] = true
container_names["express-underground-belt-container"] = true

local ignore_next_event = false

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

  for key, orphan in pairs(storage.belt_orphans_ticking) do
    local itemstack = orphan.container.get_inventory(defines.inventory.chest).get_contents()[1]
    if itemstack and itemstack.count > 0 then
      make_removal_request(orphan)
    else
      orphan.container.destroy()
      storage.belt_orphans_ticking[key] = nil
      storage.belt_orphans[key] = nil
    end
  end
end)

function clear_storage()
  storage.belt_pairs = {}
  storage.belt_pairs_ticking = {}
  storage.belt_orphans = {}
  storage.belt_orphans_ticking = {}
end

-- handle player placing underground belts + ghosts
script.on_event(defines.events.on_built_entity, function(event) 
  --game.print("on built entity")
  local entity = event.entity
  if not (
    (entity.name == "entity-ghost" and entity.ghost_type == "underground-belt")
    or (entity.type == "underground-belt")
    ) then return end
  -- entity is an underground belt or a ghost of one
  
  local neighbour = entity.neighbours --connected underground
  if neighbour and neighbour.type == "underground-belt" then
    -- check for existing connection
    local itemstack
    local neighbour_connection = storage.belt_pairs[pos_string(neighbour)]
    if neighbour_connection then
      if neighbour_connection[entity.belt_to_ground_type] == entity then
        return --duplicate connection
      else
        itemstack = break_connection(neighbour_connection)
      end
    end

    if entity.type == "underground-belt" then
      local player = game.get_player(event.player_index)
      new_connection(player, entity, neighbour, itemstack)
    elseif itemstack then
      make_orphan(neighbour, itemstack)
    end
  end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  --game.print("on robot built entity")
  local entity = event.entity
  if not (entity.type == "underground-belt") then return end

  local connection = storage.belt_pairs[pos_string(entity)]
  local orphan = storage.belt_orphans[pos_string(entity)]

  if connection then
    -- TODO upgrade logic
  elseif orphan then
    -- TODO also upgrade logic
  else
    --create new connection
    local neighbour = entity.neighbours
    if neighbour and neighbour.type == "underground-belt" then
      new_connection(nil, entity, neighbour, nil)
    end
  end
  do return end

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
      storage.belt_pairs_ticking[pos_string(connection.container)] = connection
    end
  end
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
  game.print("on player mined entity")
  local entity = event.entity

  local neighbour
  local itemstack

  local orphan = storage.belt_orphans[pos_string(entity)]
  if orphan then
    orphan_mined(game.get_player(event.player_index), orphan, entity)
    return
  end

  local connection = storage.belt_pairs[pos_string(entity)]
  if connection then
    if not (entity == connection.input or entity == connection.output or entity == connection.container) then return end -- entity not part of this connection
    if not (connection.input.valid and connection.output.valid) then return end -- don't touch invalid entities
    --mined entity is part of an underground connection

    --destroy connection
    game.print("Destroying connection between "..pos_string(connection.input).." and "..pos_string(connection.output))
    local stopped = false
    if storage.belt_pairs_ticking[pos_string(connection.input)] then
      storage.belt_pairs_ticking[pos_string(connection.input)] = nil
      stopped = true
    end
    storage.belt_pairs[pos_string(connection.input)] = nil
    storage.belt_pairs[pos_string(connection.output)] = nil

    --cleanup
    local container = connection.container
    
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
    if new_neighbour and new_neighbour.type == "underground-belt" then
      new_connection(game.get_player(event.player_index), neighbour, new_neighbour, itemstack)
      itemstack = nil
    end

    if itemstack then
      event.buffer.insert(itemstack) -- TODO handle full inventory
    end
    return
  end

  if entity.name == "entity-ghost" and entity.ghost_type == "underground-belt" then
    neighbour = entity.neighbours
    if not neighbour then return end
    entity.destroy()
    if neighbour.neighbours and neighbour.neighbours.name ~= "entity-ghost" then
      new_connection(nil, neighbour, neighbour.neighbours, nil)
    end
  end
end)

local delayed_update = {}

script.on_event(defines.events.on_pre_ghost_deconstructed, function(event)
  if ignore_next_event or event.ghost.ghost_type ~= "underground-belt" then return end
  --game.print(event.tick.." pre ghost deconstructed "..pos_string(event.ghost))

  local using_planner = false
  local cursorstack = game.get_player(event.player_index).cursor_stack
  if cursorstack and cursorstack.valid_for_read and cursorstack.type == "deconstruction-item" then
      using_planner = true
  end

  -- update neighbour
  local neighbour = event.ghost.neighbours
  if neighbour and neighbour.type == "underground-belt" then
    event.ghost.destroy()
    if using_planner then
      table.insert(delayed_update, neighbour)
    else
      if neighbour.neighbours and neighbour.neighbours.type == "underground-belt" then
        new_connection(nil, neighbour, neighbour.neighbours, nil)
      end
    end
  end
end)

script.on_event(defines.events.on_marked_for_deconstruction, function(event)
  if ignore_next_event or event.entity.type ~= "underground-belt" then return end
  --game.print(event.tick.." marked "..event.entity.name.." for deconstruction "..pos_string(event.entity))

  local entity = event.entity

  local connection = storage.belt_pairs[pos_string(event.entity)]
  if connection and (entity == connection.input or entity == connection.output or entity == connection.container) then
    local container = connection.container
    if container and entity == container then
      entity = connection.input
    end

    local itemstack = break_connection(connection)
    if storage.belt_pairs_ticking[pos_string(connection.input)] then
      storage.belt_pairs_ticking[pos_string(connection.input)] = nil
    end

    -- make orphaned belt
    ignore_next_event = true
    if itemstack then
      container = spawn_container(entity)
      container.insert(itemstack)
      container.order_deconstruction(entity.force, event.player_index)
      entity = stop_belt(entity)
      entity.cancel_deconstruction(entity.force)

      storage.belt_orphans[pos_string(entity)] = {belt=entity, container=container}
      --game.print("new orphan at "..pos_string(entity))
    else
      entity = start_belt(entity)
      entity.order_deconstruction(entity.force, event.player_index, 1)
    end
    ignore_next_event = false
    
    -- update neighbour (guaranteed to exist if connection is valid)
    local using_planner = false
    local cursorstack = game.get_player(event.player_index).cursor_stack
    if cursorstack and cursorstack.valid_for_read and cursorstack.type == "deconstruction-item" then
        using_planner = true
    end

    local neighbour
    if entity.belt_to_ground_type == "input" then
      neighbour = connection.output
    else
      neighbour = connection.input
    end
    if using_planner then
      table.insert(delayed_update, neighbour)
    else
      if neighbour.neighbours and neighbour.neighbours.name ~= "entity-ghost" then
        new_connection(nil, neighbour, neighbour.neighbours, nil)
      end
    end
    return
  end

  local orphan = storage.belt_orphans[pos_string(entity)]
  if orphan and (entity == orphan.belt or entity == orphan.container) then
    ignore_next_event = true
    storage.belt_orphans_ticking[pos_string(entity)] = nil
    orphan.container.order_deconstruction(entity.force, event.player_index)
    orphan.belt.cancel_deconstruction(entity.force)
    orphan.belt = stop_belt(orphan.belt)
    ignore_next_event = false
    return
  end
end)

script.on_event(defines.events.on_cancelled_deconstruction, function(event)
  if ignore_next_event then return end
  game.print(event.tick.." cancelled deconstruction "..pos_string(event.entity))

  local entity = event.entity
  local orphan = storage.belt_orphans[pos_string(entity)]
  if orphan and entity == orphan.container then
    orphan.belt = start_belt(orphan.belt)
    entity = orphan.belt
    make_removal_request(orphan)
  end

  if entity.type == "underground-belt" then
    local neighbour = entity.neighbours --connected underground
    if neighbour and neighbour.type == "underground-belt" then
      local itemstack
      local neighbour_connection = storage.belt_pairs[pos_string(neighbour)]
      if neighbour_connection then
        itemstack = break_connection(neighbour_connection)
      end
      new_connection(nil, neighbour, entity, itemstack)
    end
  end
end)

-- NOTE: always called last when using the planner, which makes it useful as a delayed update
script.on_event(defines.events.on_player_deconstructed_area, function(event)
  --game.print(event.tick.." on player deconstruction area")
  for index, entity in ipairs(delayed_update) do
    if entity.valid and entity.neighbours and entity.neighbours.name ~= "entity-ghost"
      and (not storage.belt_pairs[pos_string(entity)]) 
      and (not (storage.belt_orphans[pos_string(entity)] and storage.belt_orphans[pos_string(entity)].container.to_be_deconstructed() )) then
      new_connection(nil, entity, entity.neighbours, nil)
    end
  end
  delayed_update = {}
end)

-- upgrading ghosts
-- TODO handle downgrades which break belt connections
script.on_event(defines.events.on_pre_ghost_upgraded, function(event)
  if event.target.type ~= "underground-belt" then return end
  do return end

  local connection = storage.belt_pairs[pos_string(event.ghost)]
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
  do return end

  local connection = storage.belt_pairs[pos_string(event.entity)]
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
  local orphan = storage.belt_orphans[pos_string(event.entity)]
  if orphan then orphan_mined(nil, orphan, event.entity) end
end)

function pos_string(entity)
  return entity.position.x.." "..entity.position.y
end

function get_underground_distance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

function new_connection(player, entity, neighbour, itemstack)
  if entity.name == "entity-ghost" or neighbour.name == "entity-ghost" then 
    dump_itemstack(player, entity, itemstack)
  end

  game.print("new connection from "..pos_string(entity).." to "..pos_string(neighbour))

  local underground_name = entity.name
  local belt_name = belt_names[underground_name] --related transport belt prototype

  local connection = {} --{input, output, name, length, container, request}
  storage.belt_pairs[pos_string(entity)] = connection
  storage.belt_pairs[pos_string(neighbour)] = connection
  
  connection[entity.belt_to_ground_type] = entity
  connection[neighbour.belt_to_ground_type] = neighbour
  connection.name = underground_name
  local length = get_underground_distance(entity.position, neighbour.position)
  connection.length = length

  -- check for orphans
  local orphan = storage.belt_orphans[pos_string(entity)]
  if orphan then
    itemstack = unmake_orphan(orphan) -- NOTE: itemstack will be nil if entity is an orphan, so this is ok
  end

  orphan = storage.belt_orphans[pos_string(neighbour)]
  if orphan then
    local itemstack2 = unmake_orphan(orphan)
    if itemstack then
      if itemstack2.name == itemstack.name then
        itemstack.count = itemstack.count + itemstack2.count
      else
        dump_itemstack(player, entity, itemstack2)
      end
    else
      itemstack = itemstack2
    end
  end

  local belts = 0
  if itemstack and itemstack.name == belt_name then
    belts = itemstack.count
  end

  -- manual placement logic
  if player then
    if itemstack and itemstack.name ~= belt_name then --refund irrelevant belts to the player
      dump_itemstack(player, entity, itemstack)
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
      dump_itemstack(player, entity, itemstack)
      itemstack = nil
      belts = length
    end
  end

  if belts ~= length then
    -- create storage container
    local container = spawn_container(connection.input)
    connection.container = container

    -- stop the underground belt
    connection.input = stop_belt(connection.input)
    connection.output = stop_belt(connection.output)
    storage.belt_pairs_ticking[pos_string(container)] = connection

    if itemstack then
      itemstack.count = itemstack.count - container.get_inventory(defines.inventory.chest).insert(itemstack)
      if itemstack.count > 0 then
        dump_itemstack(player, entity, itemstack)
      end
    end
    make_request_proxy(connection)
  end
end

function break_connection(connection)
  game.print("breaking connection between "..pos_string(connection.input).." and "..pos_string(connection.output))

  --clear storage values
  storage.belt_pairs[pos_string(connection.input)] = nil
  storage.belt_pairs[pos_string(connection.output)] = nil

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

function make_orphan(entity, itemstack)
  local container = spawn_container(entity)
  container.insert(itemstack)
  local orphan = {belt=entity, container=container}
  make_removal_request(orphan)
  storage.belt_orphans[pos_string(entity)] = orphan
  storage.belt_orphans_ticking[pos_string(entity)] = orphan
end

function unmake_orphan(orphan)
  local container = orphan.container
  local itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
  container.destroy()
  storage.belt_orphans[pos_string(orphan.belt)] = nil
  storage.belt_orphans_ticking[pos_string(orphan.belt)] = nil
  return itemstack
end

function orphan_mined(player, orphan, entity)
  if orphan.container == entity then
    orphan.belt.destroy()
    storage.belt_orphans[pos_string(entity)] = nil
    storage.belt_orphans_ticking[pos_string(entity)] = nil
  elseif orphan.belt == entity then
    local itemstack = orphan.container.get_inventory(defines.inventory.chest).get_contents()[1]
    if itemstack then
      dump_itemstack(player, entity, itemstack)
    end
    orphan.container.destroy()
    storage.belt_orphans[pos_string(entity)] = nil
    storage.belt_orphans_ticking[pos_string(entity)] = nil
  end
end

function dump_itemstack(player, entity, itemstack)
  if player then
    player.insert(itemstack) -- does not show text / does not handle full inventory. TODO fix this
  else
    entity.surface.spill_item_stack{
      position=entity.position,
      stack=itemstack,
      force=entity.force,
      allow_belts=false
    }
  end
end

function spawn_container(entity)
  local underground_name = entity.name
  if entity.name == "entity-ghost" then
    underground_name = entity.ghost_name
  elseif string.match(entity.name, "-stopped") then
    underground_name = string.sub(underground_name, 1, underground_name:len()-8)
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

function make_removal_request(orphan)
  local container = orphan.container
  local request = orphan.request
  local itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
  local removal_plan = {}

  if itemstack then
    removal_plan = make_insert_plan(itemstack.name, itemstack.count)
  end

  if request and request.valid and request.proxy_target == container then
    request.removal_plan = removal_plan
  else
    orphan.request = container.surface.create_entity{
      name = "item-request-proxy",
      position = container.position,
      force = container.force,
      target = container,
      modules = {},
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
  end
  connection.request = nil
end

function stop_belt(entity)
  if not string.match(entity.name, "-stopped") then
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
  end
  return entity
end

function start_belt(entity)
  if string.match(entity.name, "-stopped") then
    entity = entity.surface.create_entity{
      name = string.sub(entity.name, 1, entity.name:len()-8),
      position = entity.position,
      force = entity.force,
      direction = entity.direction,
      type = entity.belt_to_ground_type,
      fast_replace = true,
      spill = false
    }
  end
  return entity
end