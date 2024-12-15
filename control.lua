script.on_init(function()
	storage.undergrounds = {}
  storage.id_counter = 1
end)

script.on_nth_tick(5, function()
  for key, underground in pairs(storage.undergrounds) do
    local length = get_underground_distance(underground.belt.position, underground.belt.neighbours.position)
    local inventory = underground.container.get_inventory(defines.inventory.chest)
    if inventory.get_contents()[1] and inventory.get_contents()[1].count == length then
      inventory.clear()
      underground.container.destroy()
      local pos = position_to_string(underground.belt.neighbours.position)
      storage.undergrounds[pos].container.destroy()
      start_belt(underground.belt.neighbours)
      storage.undergrounds[pos] = nil
      start_belt(underground.belt)
      storage.undergrounds[key] = nil
    end
  end
end)

function update_underground(pos)
  
end

script.on_event(defines.events.on_built_entity, function(event)
  underground_placed(event.entity, game.get_player(event.player_index))
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  underground_placed(event.entity)
end)

function underground_placed(entity, player)
  if entity.type == "underground-belt" then
    local name = entity.name
    local neighbour = entity.neighbours
    if neighbour then
      local length = get_underground_distance(entity.position, neighbour.position)
      local count = 0
      entity = stop_belt(entity)
      neighbour = stop_belt(neighbour)
      local container = entity.surface.create_entity{
        name = name.."-container",
        position = entity.position,
        force = entity.force,
        spill = false
      }
      container.link_id = storage.id_counter
      storage.undergrounds[position_to_string(entity.position)] = {belt = entity, container = container}
      container = entity.surface.create_entity{
        name = name.."-container",
        position = neighbour.position,
        force = neighbour.force,
        spill = false
      }
      container.link_id = storage.id_counter
      storage.undergrounds[position_to_string(neighbour.position)] = {belt = neighbour, container = container}
      storage.id_counter = storage.id_counter + 1

      if player then
        count = player.remove_item({name="transport-belt", count=length})
        if count > 0 then
          container.get_inventory(defines.inventory.chest).insert({name="transport-belt", count=count})
        end
      end
      if (count < length) then
        make_request(container, "transport-belt", length - count)
      end
    end
  end
end

script.on_event(defines.events.on_player_mined_entity, function(event)
  underground_removed(event.entity, event.buffer)
end)

script.on_event(defines.events.on_robot_mined_entity, function(event)
  underground_removed(event.entity, event.buffer)
end)

function underground_removed(entity, buffer)
  pos = position_to_string(entity.position)
  -- deconstructing unfinished underground connections
  if storage.undergrounds[pos] ~= nil then
    local inventory = entity.get_inventory(defines.inventory.chest)
    local items = inventory.get_contents()[1]
    if items then
      buffer.insert(items)
    end
    inventory.clear()
    local underground = storage.undergrounds[pos]
    local neighbour = underground.belt.neighbours
    underground.belt.destroy()
    storage.undergrounds[pos] = nil
    if neighbour then 
      pos = position_to_string(neighbour.position)
      if storage.undergrounds[pos] then
        underground = storage.undergrounds[pos]
        underground.container.destroy()
        start_belt(underground.belt)
        storage.undergrounds[pos] = nil
      end
    end
    -- deconstructing completed underground connections
  elseif entity.type == "underground-belt" then
    local neighbour = entity.neighbours
    if neighbour then
      local length = get_underground_distance(entity.position, neighbour.position)
      buffer.insert({name="transport-belt", count=length})
      -- TODO -- refresh neighbouring belt
    end
  end
end

function get_underground_distance(pos1, pos2)
  return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

function position_to_string(pos)
  return pos.x.." "..pos.y
end

function check_storage()
  if not storage.undergrounds then
    storage.undergrounds = {}
  end
  if not storage.id_counter then
    storage.id_counter = 1
  end
end

function stop_belt(entity)
  return entity.surface.create_entity{
    name = entity.name.."-stopped",
    position = entity.position,
    force = entity.force,
    direction = entity.direction,
    type = entity.belt_to_ground_type,
    fast_replace = true,
    spill = false
  }
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