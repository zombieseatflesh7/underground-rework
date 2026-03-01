local ub = data.raw["underground-belt"]["underground-belt"]
local space_age = mods["space-age"]
local cheaper_recipes = settings.startup["cheaper-recipes"]
local double_stack = settings.startup["double-stack-size"].value
local min_length = settings.startup["minimum-length"].value + 1

local c = {
    type = "container",
    name = "underground-rework-container",
    flags = {"player-creation", "not-repairable", "not-on-map", "not-deconstructable", "not-blueprintable", "not-upgradable", "no-automated-item-removal", "no-automated-item-insertion", "not-in-kill-statistics", "no-copy-paste", "not-in-made-in"},
    collision_box = ub.collision_box,
    collision_mask = {layers = {}},
    selection_box = ub.selection_box,
    selectable_in_game = false,
    inventory_size = 1,
    inventory_type = "normal"
}
data:extend{c}

if cheaper_recipes then
  local recipe = data.raw["recipe"]["underground-belt"]
  recipe.ingredients[1].amount = 6
  recipe.ingredients[2].amount = 3
  recipe = data.raw["recipe"]["fast-underground-belt"]
  recipe.ingredients[1].amount = 15
  recipe = data.raw["recipe"]["express-underground-belt"]
  recipe.ingredients[1].amount = 30
  recipe.ingredients[3].amount = 60
  if space_age then
    recipe = data.raw["recipe"]["turbo-underground-belt"]
    recipe.ingredients[1].amount = 15
    recipe.ingredients[3].amount = 60
  end
end

local ub_prototypes = {"underground-belt", "fast-underground-belt", "express-underground-belt"}
if space_age then table.insert(ub_prototypes, "turbo-underground-belt") end

if double_stack then
  for _, name in pairs(ub_prototypes) do
    local item = data.raw["item"][name]
    item.stack_size = item.stack_size * 2
  end
end
if min_length > 1 then
  for _, name in pairs(ub_prototypes) do
    local prototype = data.raw["underground-belt"][name]
    if prototype.max_distance < min_length then prototype.max_distance = min_length end
  end
end
