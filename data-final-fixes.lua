local ub = data.raw["underground-belt"]["underground-belt"]

for _, v in pairs(data.raw["transport-belt"]) do
    local x = table.deepcopy(data.raw["underground-belt"][v.related_underground_belt])
    local name = x.name
    x.name = name .. "-stopped"
    x.localised_name = {"entity-name." .. name}
    x.localised_description = {"entity-description." .. name}
    x.speed = 1e-308 --speed has to be positive, this is close enough to 0
    local c = {
        type = "container",
        name = name .. "-container",
        localised_name = x.localised_name,
        localised_description = x.localised_description,
        flags = {"player-creation", "not-blueprintable", "not-deconstructable", "not-upgradable", "no-automated-item-removal", "no-automated-item-insertion"},
        collision_box = x.collision_box,
        --collision_mask = {layers = {water_tile=true, floor=true}},
        collision_mask = {layers = {}},
        selection_box = x.selection_box,
        selectable_in_game = true,
        selection_priority = 46,
        max_health = x.max_health,
        resistances = x.resistances,
        minable = x.minable,
        fast_replaceable_group = "underground-rework-underground-belt-container",
        inventory_size = 1,
        inventory_type = "normal"
        --gui_mode = "none"
    }
    data:extend{x, c}
end
