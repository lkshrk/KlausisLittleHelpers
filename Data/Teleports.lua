local _, ns = ...
if ns.IS_FOREVER == false then return end

-- Spells from SpellName (build 1.60.1.71037); landings from MaNGOS Zero spell_target_position, wx = server y, wy = server x.
ns.Teleports = {
    { spellID = 3561, name = "Stormwind", side = "A", reagent = 17031, instance = 0, wx = 870, wy = -9003 },
    { spellID = 3562, name = "Ironforge", side = "A", reagent = 17031, instance = 0, wx = -915, wy = -4614 },
    { spellID = 3565, name = "Darnassus", side = "A", reagent = 17031, instance = 1, wx = 2526, wy = 9664 },
    { spellID = 3567, name = "Orgrimmar", side = "H", reagent = 17031, instance = 1, wx = -4222, wy = 1470 },
    { spellID = 3563, name = "Undercity", side = "H", reagent = 17031, instance = 0, wx = 61, wy = 1773 },
    { spellID = 3566, name = "Thunder Bluff", side = "H", reagent = 17031, instance = 1, wx = 283, wy = -965 },
}
