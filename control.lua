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

-- TODO optimize?
script.on_nth_tick(12, function()
  local count = 0

  for key, connection in pairs(storage.belt_pairs_ticking) do
    --game.print("ticking "..key)
    count = count + 1
    local itemstack = connection.container.get_inventory(defines.inventory.chest).get_contents()[1]
    if itemstack and itemstack.name == belt_names[connection.name] and itemstack.count == connection.length then
      connection.container.destroy()
      connection.container = nil
      connection.request = nil
      -- TODO: clear status
      storage.belt_pairs_ticking[key] = nil
    else
      make_request_proxy(connection)
    end
  end

  for key, orphan in pairs(storage.belt_orphans_ticking) do
    count = count + 1
    local itemstack = orphan.container.get_inventory(defines.inventory.chest).get_contents()[1]
    if itemstack and itemstack.count > 0 then
      make_removal_request(orphan)
    else
      orphan.container.destroy()
      storage.belt_orphans_ticking[key] = nil
      storage.belt_orphans[key] = nil
    end
  end

  if count > 0 then game.print("ticking "..count.." entities") end
end)

-- only for debugging
function clear_storage()
  storage.belt_pairs = {}
  storage.belt_pairs_ticking = {}
  storage.belt_orphans = {}
  storage.belt_orphans_ticking = {}
end

-- handle player placing underground belts + ghosts
script.on_event(defines.events.on_built_entity, function(event) 
  local entity = event.entity
  if entity.name == "entity-ghost"
  then game.print(event.tick.." player built ghost at "..pos_string(event.entity))
  else game.print(event.tick.." player built underground at "..pos_string(event.entity))
  end

  attempt_new_connection(game.get_player(event.player_index), entity, nil)
end, {{filter = "type", type = "underground-belt"}, {filter = "ghost_type", type = "underground-belt"}})

script.on_event(defines.events.on_robot_built_entity, function(event)
  game.print(event.tick.." robot built underground at "..pos_string(event.entity))
  
  local entity = event.entity
  local connection = storage.belt_pairs[pos_string(entity)]
  if connection and entity.name == connection.name then -- when upgrading, the connection is already made before the 2nd call of robot built entity
    connection[entity.belt_to_ground_type] = entity
  else
    -- fix invalid belt as a result of upgrading
    local orphan = storage.belt_orphans[pos_string(entity)]
    if orphan then orphan.belt = entity end
    attempt_new_connection(nil, entity, nil)
  end
end, {{filter = "type", type = "underground-belt"}})

script.on_event(defines.events.on_player_mined_entity, function(event)
  local entity = event.entity
  if entity.name == "entity-ghost"
  then game.print(event.tick.." player mined ghost at "..pos_string(event.entity))
  else game.print(event.tick.." player mined underground at "..pos_string(event.entity))
  end

  local neighbour
  local itemstack
  local orphan = storage.belt_orphans[pos_string(entity)]
  local connection = storage.belt_pairs[pos_string(entity)]

  if orphan then
    itemstack = orphan_mined(orphan, entity)

  elseif connection then
    if not (entity == connection.input or entity == connection.output) then return end -- entity not part of this connection
    if not (connection.input.valid and connection.output.valid) then return end -- don't touch invalid entities
    --mined entity is part of an underground connection

    itemstack = break_connection(connection)
    -- check neighbour for new connections
    neighbour = entity.neighbours
    entity.destroy()
    itemstack = attempt_new_connection(game.get_player(event.player_index), neighbour, itemstack)

  elseif entity.name == "entity-ghost" then
    neighbour = entity.neighbours
    entity.destroy()
    if neighbour and neighbour.name ~= "entity-ghost" and neighbour.neighbours and neighbour.neighbours.name ~= "entity-ghost" then
      new_connection(nil, neighbour, neighbour.neighbours, nil)
    end
  end

  if itemstack then
      event.buffer.insert(itemstack)
  end
end, {{filter = "type", type = "underground-belt"}, {filter = "ghost_type", type = "underground-belt"}})

script.on_event(defines.events.on_pre_ghost_deconstructed, function(event)
  game.print(event.tick.." ghost deconstructed at "..pos_string(event.ghost))

  -- update neighbour
  local neighbour = event.ghost.neighbours
  if neighbour and neighbour.type == "underground-belt" then
    event.ghost.destroy()
    if neighbour.neighbours and neighbour.neighbours.type == "underground-belt" then
      new_connection(nil, neighbour, neighbour.neighbours, nil)
    end
  end
end, {{filter = "type", type = "underground-belt"}})

script.on_event(defines.events.on_marked_for_deconstruction, function(event)
  game.print(event.tick.." marked for deconstruction at "..pos_string(event.entity))

  local entity = event.entity
  local connection = storage.belt_pairs[pos_string(entity)]
  if connection and (entity == connection.input or entity == connection.output) then
    -- make orphaned belt
    local itemstack = break_connection(connection)
    if itemstack then
      local container = spawn_container(entity)
      container.insert(itemstack)
      storage.belt_orphans[pos_string(entity)] = {belt=entity, container=container}
      game.print("new orphan at "..pos_string(entity))
    end
    
    -- update neighbour (guaranteed to exist if connection is valid)
    local neighbour = get_neighbour(entity, connection)
    if neighbour then attempt_new_connection(nil, neighbour, nil) end
    return
  end

  local orphan = storage.belt_orphans[pos_string(entity)]
  if orphan and (entity == orphan.belt) then
    storage.belt_orphans_ticking[pos_string(entity)] = nil
  end
end, {{filter = "type", type = "underground-belt"}})

script.on_event(defines.events.on_cancelled_deconstruction, function(event)
  game.print(event.tick.." cancelled deconstruction "..pos_string(event.entity))

  local entity = event.entity
  local orphan = storage.belt_orphans[pos_string(entity)]
  if orphan and entity == orphan.belt then
    make_removal_request(orphan)
  end

  local neighbour = entity.neighbours --connected underground
  if neighbour and neighbour.type == "underground-belt" then
    local itemstack
    local neighbour_connection = storage.belt_pairs[pos_string(neighbour)]
    if neighbour_connection then
      itemstack = break_connection(neighbour_connection)
    end
    new_connection(nil, neighbour, entity, itemstack)
  end
end, {{filter = "type", type = "underground-belt"}})

local delayed_update = {}
script.on_event(defines.events.on_pre_ghost_upgraded, function(event)
  local ghost = event.ghost
  game.print(event.tick.." ghost upgraded at "..pos_string(ghost))
  
  delayed_update[pos_string(ghost)] = ghost
  local neighbour = ghost.neighbours
  if neighbour then delayed_update[pos_string(neighbour)] = neighbour end
end, {{filter = "type", type = "underground-belt"}})

script.on_event(defines.events.on_tick, function(event)
  for key, entity in pairs(delayed_update) do
    dump_itemstack(nil, entity, attempt_new_connection(nil, entity, nil))
  end
  delayed_update = {}
end)

script.on_event(defines.events.on_marked_for_upgrade, function(event)
  game.print(event.tick.." marked for upgrade at "..pos_string(event.entity))
  local entity = event.entity
  local connection = storage.belt_pairs[pos_string(entity)]
  if connection then 
    local itemstack = break_connection(connection) 
    if itemstack then make_orphan(entity, itemstack) end
  end
end, {{filter = "type", type = "underground-belt"}})

script.on_event(defines.events.on_cancelled_upgrade, function(event)
  game.print(event.tick.." cancelled upgrade at "..pos_string(event.entity))
  attempt_new_connection(nil, event.entity, nil)
end, {{filter = "type", type = "underground-belt"}})

function attempt_new_connection(player, entity, returnstack)
  local neighbour = entity.neighbours
  if neighbour and neighbour.name ~= "entity-ghost" and (not neighbour.to_be_upgraded()) then 
    -- fix invalid belt because of bots upgrading
    local orphan = storage.belt_orphans[pos_string(neighbour)]
    if orphan then orphan.belt = neighbour end
    -- check for broken connections as a result of this entity being placed
    local itemstack
    local neighbour_connection = storage.belt_pairs[pos_string(neighbour)]
    if neighbour_connection then
      if neighbour_connection[entity.belt_to_ground_type] == entity then return returnstack end
      itemstack = break_connection(neighbour_connection) 
    end
    if not itemstack then 
      itemstack = returnstack
      returnstack = nil
    end
    if entity.name == "entity-ghost" then
      make_orphan(neighbour, itemstack)
    else
      new_connection(player, entity, neighbour, itemstack)
    end
  end
  return returnstack
end

script.on_event(defines.events.on_robot_mined_entity, function(event)
  game.print(event.tick.." robot mined underground at "..pos_string(event.entity))

  local orphan = storage.belt_orphans[pos_string(event.entity)]
  if orphan and (not event.entity.to_be_upgraded()) then -- deconstructing (but not upgrading)
    local itemstack = orphan_mined(orphan, event.entity) 
    if itemstack then event.buffer.insert(itemstack) end -- drop items on ground
  end
end, {{filter = "type", type = "underground-belt"}})

function pos_string(entity)
  return entity.position.x-0.5 .. " " .. entity.position.y-0.5
  --return entity.unit_number
end

function get_underground_distance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

function new_connection(player, entity, neighbour, itemstack)
  if (entity.name == "entity-ghost" or neighbour.name == "entity-ghost" or entity.to_be_upgraded() or neighbour.to_be_upgraded()) then 
    if itemstack then dump_itemstack(player, entity, itemstack) end
    return
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
    local itemstack2 = unmake_orphan(orphan)
    if itemstack2 then
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
  end

  orphan = storage.belt_orphans[pos_string(neighbour)]
  if orphan then
    local itemstack2 = unmake_orphan(orphan)
    if itemstack2 then
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
    storage.belt_pairs_ticking[pos_string(container)] = connection

    if itemstack then
      itemstack.count = itemstack.count - container.insert(itemstack)
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
    storage.belt_pairs_ticking[pos_string(container)] = nil
    itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
    container.destroy()
  else
    itemstack = {name=belt_names[connection.name], count=connection.length}
  end

  --if itemstack then game.print(itemstack.name.." "..itemstack.count) end
  return itemstack
end

function get_neighbour(entity, connection)
  if entity == connection.input then
    return connection.output
  else
    return connection.input
  end
end

function get_upgrade(entity)
  local prototype, quality = entity.get_upgrade_target()
  if (prototype) then return prototype.name 
  else return entity.name end
end

function make_orphan(entity, itemstack)
  game.print("making orphan at "..pos_string(entity))
  local container = spawn_container(entity)
  container.insert(itemstack)
  local orphan = {belt=entity, container=container}
  make_removal_request(orphan)
  storage.belt_orphans[pos_string(entity)] = orphan
  storage.belt_orphans_ticking[pos_string(entity)] = orphan
end

function unmake_orphan(orphan)
  game.print("destroying orphan at "..pos_string(orphan.belt))
  local container = orphan.container
  local itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
  container.destroy()
  storage.belt_orphans[pos_string(orphan.belt)] = nil
  storage.belt_orphans_ticking[pos_string(orphan.belt)] = nil
  return itemstack
end

function orphan_mined(orphan, entity)
  local itemstack
  if orphan.container then
    itemstack = orphan.container.get_inventory(defines.inventory.chest).get_contents()[1]
    orphan.container.destroy()
  end
  storage.belt_orphans[pos_string(entity)] = nil
  storage.belt_orphans_ticking[pos_string(entity)] = nil
  return itemstack
end

function dump_itemstack(player, entity, itemstack)
  if not itemstack then return end
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
  local container = entity.surface.create_entity{
    name = "underground-rework-container",
    position = entity.position,
    force = entity.force,
    spill = false
  }
  container.destructible = false
  return container
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