local cheaper_recipes = settings.startup["cheaper-recipes"]
local double_stack = settings.startup["double-stack-size"].value
local min_length = settings.startup["minimum-length"].value + 1

-- invisible container entity for holding belts
data:extend{{
    type = "container",
    name = "underground-rework-container",
    flags = {"player-creation", "not-repairable", "not-on-map", "not-deconstructable", "not-blueprintable", "not-upgradable", "no-automated-item-removal", "no-automated-item-insertion", "not-in-kill-statistics", "no-copy-paste", "not-in-made-in"},
    collision_box = data.raw["underground-belt"]["underground-belt"].collision_box,
    collision_mask = {layers = {}},
    selection_box = data.raw["underground-belt"]["underground-belt"].selection_box,
    selectable_in_game = false,
    inventory_size = 1,
    inventory_type = "normal"
}}

local ub_prototypes = data.raw["underground-belt"]

for ub_name, prototype in pairs(ub_prototypes) do
  -- stack size tweak
  local item = data.raw.item[ub_name]
  if double_stack and item then
    item.stack_size = item.stack_size * 2
  end

  -- max length tweak
  if min_length > 1 and prototype.max_distance < min_length then
    prototype.max_distance = min_length 
  end

  -- automatic recipe tweaks
  local ub_recipe = data.raw.recipe[ub_name]
  if cheaper_recipes and ub_recipe then
    for _, ingredient in pairs(ub_recipe.ingredients) do
      -- if made from transport belts, reduce to 3
      if ingredient.type == "item" and data.raw["transport-belt"][ingredient.name] and ingredient.amount > 3 then 
        ingredient.amount = 3
        goto continue_recipe

      -- if made from previous tier underground belt
      elseif ingredient.type == "item" and data.raw["underground-belt"][ingredient.name] then
        -- get corresponding transport belt recipe
        local tb_name = string.gsub(ub_name, "underground%-belt", "transport-belt") -- standard naming convention
        if tb_name == ub_name then tb_name = string.gsub(ub_name, "%-underground", "-belt") end -- lazy naming convention
        if tb_recipe ~= ub_recipe and data.raw.recipe[tb_name] then -- recipe exists and is not the ub recipe
          -- get values from transport belt recipe and apply them to the underground belt recipe x3
          local tb_recipe = data.raw.recipe[tb_name]
          local tp = tb_recipe.results[1]
          local factor = 1
          if tp.name == tb_name then factor = tp.amount end
          for _, ui in pairs(ub_recipe.ingredients) do
            if ui.name == "fluoroketone-cold" then goto next_ingredient end -- skip fluoroketone
            for _, ti in pairs(tb_recipe.ingredients) do
              if ui.type == ti.type and ui.name == ti.name then 
                ui.amount = math.ceil(ti.amount * 3 / factor)
                goto next_ingredient
              end
            end
            ::next_ingredient::
          end
        end
        goto continue_recipe
      end

    end
    ::continue_recipe:: -- skipping to next ub recipe
  end
end

-- manual recipe tweaks
if cheaper_recipes then
  -- base underground belt
  local recipe = data.raw.recipe["underground-belt"]
  if recipe then
    local i = recipe.ingredients[1]
    if i and i.type == "item" and i.name == "iron-plate" and i.amount == 10 then i.amount = 6 end
  end

  -- custom recipe
  if mods["AdvancedBeltsSA"] then
    local i = data.raw.recipe["extreme-underground"].ingredients
    i[2].amount = 8
    i[3].amount = 4
    i[4].amount = 40
    local i = data.raw.recipe["ultimate-underground"].ingredients
    i[2].amount = 20
    i[3].amount = 20
    local i = data.raw.recipe["high-speed-underground"].ingredients
    i[2].amount = 10
  end
end
