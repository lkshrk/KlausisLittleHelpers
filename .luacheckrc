std = "lua51"
max_line_length = false
unused_args = false
exclude_files = { "Libs/**", ".release/**", ".ctxtmp/**", ".worktrees/**" }
read_globals = {
    "STANDARD_TEXT_FONT", "GameTooltip", "MenuUtil",
    "CreateFrame", "C_Timer", "InCombatLockdown", "ReloadUI", "geterrorhandler", "hooksecurefunc",
    "CreateMacro", "DeleteMacro", "EditMacro", "GetMacroIndexByName", "GetNumMacros",
    "print", "wipe", "CopyTable",
    "GameRulesUtil", "GetMaxLevelForPlayerExpansion", "GetTime", "UnitLevel", "UnitXP", "UnitXPMax",
    "C_QuestLog", "C_Map", "C_TaxiMap", "Enum", "UnitFactionGroup", "UIParent", "IsControlKeyDown", "GetUnitSpeed", "IsMounted", "UnitOnTaxi", "GetTaxiMapID", "GetNumRoutes", "TaxiGetNodeSlot", "C_Item", "C_Container", "C_SpellBook", "GetBindLocation", "GetQuestID", "C_CurrencyInfo", "C_Reputation", "Auctionator", "time",
}
globals = { "KLH", "KLH_DB", "KLH_CharDB", "SlashCmdList", "SLASH_KLH1", "SLASH_KLH2", "SLASH_KLH3" }
files[".tools/**"] = { std = "lua51", read_globals = {}, globals = {} }
files[".tools/tests/**"] = { read_globals = { "eq", "ok", "find", "has", "addon" }, globals = { "ns" } }
files["Modules/TustUIXPBar.lua"] = { read_globals = { "EllesmereUI", "EUI_CLIENT_BLOCKED" } }
