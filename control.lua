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

-- TODO rewrite
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
end, {{filter = "type", type = "underground-belt"}, {filter = "ghost_type", type = "underground-belt"}})

script.on_event(defines.events.on_robot_built_entity, function(event)
  game.print(event.tick.." robot built underground at "..pos_string(event.entity))
  local entity = event.entity
  local connection = storage.belt_pairs[pos_string(entity)]
  local orphan = storage.belt_orphans[pos_string(entity)]

  -- upgrade logic
  if connection and entity.name == connection.name then
    connection[entity.belt_to_ground_type] = entity
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
  end
  if (not neighbour.valid) and entity.neighbours then -- neighbour was upgraded
    --game.print("neighbour upgraded")
    neighbour = entity.neighbours
    connection[neighbour.belt_to_ground_type] = neighbour
  end

  if entity.name == connection.name and neighbour.name == connection.name then
    local itemstack = connection.container.get_inventory(defines.inventory.chest).get_contents()[1]
    -- has the required transport belts
    if itemstack and itemstack.name == belt_names[connection.name] and itemstack.count == connection.length then
      connection.container.destroy() -- TODO refactor this for new health system
      connection.container = nil
      connection.request = nil
    else
      storage.belt_pairs_ticking[pos_string(connection.container)] = connection
    end
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
    neighbour = entity.neighbours
    entity.destroy()

    -- check neighbour for new connections
    local new_neighbour = neighbour.neighbours
    if new_neighbour and new_neighbour.type == "underground-belt" then
      new_connection(game.get_player(event.player_index), neighbour, new_neighbour, itemstack)
      itemstack = nil
    end

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
  local connection = storage.belt_pairs[pos_string(event.entity)]
  if connection and (entity == connection.input or entity == connection.output) then
    -- make orphaned belt
    local itemstack = break_connection(connection)
    if itemstack then
      local container = spawn_container(entity)
      container.insert(itemstack)
      storage.belt_orphans[pos_string(entity)] = {belt=entity, container=container}
      --game.print("new orphan at "..pos_string(entity))
    end
    
    -- update neighbour (guaranteed to exist if connection is valid)

    local neighbour
    if entity.belt_to_ground_type == "input" then
      neighbour = connection.output
    else
      neighbour = connection.input
    end
    if neighbour and neighbour.neighbours and neighbour.neighbours.name ~= "entity-ghost" then
      new_connection(nil, neighbour, neighbour.neighbours, nil)
    end
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

script.on_event(defines.events.on_marked_for_upgrade, function(event)
  game.print(event.tick.." marked for upgrade at "..pos_string(event.entity))
  mark_for_upgrade(event.entity, event.target.name)
end, {{filter = "type", type = "underground-belt"}})

script.on_event(defines.events.on_cancelled_upgrade, function(event)
  game.print(event.tick.." cancelled upgrade at "..pos_string(event.entity))
  mark_for_upgrade(event.entity, event.target.name)
end, {{filter = "type", type = "underground-belt"}})

function mark_for_upgrade(entity, upgrade)
  local connection = storage.belt_pairs[pos_string(entity)]
  if connection then
    if connection.name ~= upgrade then
      -- upgrades happen in pairs. This effectively skips the first upgrade event.
      connection.name = upgrade
    elseif connection.input.neighbours == connection.output then
      new_connection(nil, connection.input, connection.output, break_connection(connection))
    else
      -- TODO: handle connection breaking upgrades
      local itemstack = break_connection(connection)
    end
  else
    -- TODO: upgrading orphaned or normal belts
  end
end

script.on_event(defines.events.on_robot_mined_entity, function(event)
  game.print(event.tick.." robot mined underground at "..pos_string(event.entity))
  local orphan = storage.belt_orphans[pos_string(event.entity)]
  if orphan then 
    local itemstack = orphan_mined(orphan, event.entity) 
    if itemstack then event.buffer.insert(itemstack) end
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
  if (entity.name == "entity-ghost" or neighbour.name == "entity-ghost") then 
    if itemstack then dump_itemstack(player, entity, itemstack) end
    return
  end

  game.print("new connection from "..pos_string(entity).." to "..pos_string(neighbour))

  local underground_name = entity.name
  if entity.to_be_upgraded() then 
    local prototype, quality = entity.get_upgrade_target()
    underground_name = prototype.name
  end
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
  if storage.belt_pairs_ticking[pos_string(connection.input)] then
    storage.belt_pairs_ticking[pos_string(connection.input)] = nil
  end
  storage.belt_pairs[pos_string(connection.input)] = nil
  storage.belt_pairs[pos_string(connection.output)] = nil

  --return connection contents
  local container = connection.container
  local itemstack

  if container then 
    itemstack = container.get_inventory(defines.inventory.chest).get_contents()[1]
    container.destroy()
  elseif connection.input.name == connection.output.name then
    itemstack = {name=belt_names[connection.input.name], count=connection.length}
  end

  return itemstack
end

function get_neighbour(entity, connection)
  if entity == connection.input then
    return connection.output
  else
    return connection.input
  end
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