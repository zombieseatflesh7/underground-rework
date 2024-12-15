local ub = data.raw["underground-belt"]["underground-belt"]

for _, v in pairs(data.raw["transport-belt"]) do
    local x = table.deepcopy(data.raw["underground-belt"][v.related_underground_belt])
    local name = x.name
    x.name = name .. "-stopped"
    x.localised_name = {"entity-name." .. name}
    x.localised_description = {"entity-description." .. name}
    x.speed = 1e-308 --speed has to be positive, this is close enough to 0
    table.insert(x.flags, "not-deconstructable")
    --table.remove(x.flags, )
    data:extend({x,
    {
        type = "linked-container",
        name = name .. "-container",
        flags = {"player-creation", "not-blueprintable"},
        max_health = 1,
        resistances = resistances_immune,
        collision_box = ub.collision_box,
        collision_mask = {layers = {}},
        selection_box = ub.selection_box,
        selectable_in_game = true,
        minable = x.minable,
        inventory_size = 1,
        inventory_type = "normal",
        gui_mode = "none"
    }
    })
end
