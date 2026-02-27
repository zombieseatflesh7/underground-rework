local ub = data.raw["underground-belt"]["underground-belt"]

local c = {
    type = "container",
    name = "underground-rework-container",
    flags = {"player-creation", "not-repairable", "not-on-map", "not-deconstructable", "not-blueprintable", "not-upgradable", "no-automated-item-removal", "no-automated-item-insertion", "not-in-kill-statistics", "no-copy-paste", "not-in-made-in"},
    collision_box = ub.collision_box,
    collision_mask = {layers = {}},
    selection_box = ub.selection_box,
    selectable_in_game = false,
    --minable = false,
    inventory_size = 1,
    inventory_type = "normal"
}
data:extend{c}
