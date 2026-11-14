std = "lua51"
max_line_length = false
unused_args = false
exclude_files = { "Libs/**", ".release/**", ".eui/**", ".tools/guardrails.py" }
read_globals = {
    "EllesmereUI", "EUI_CLIENT_BLOCKED",
    "CreateFrame", "C_Timer", "InCombatLockdown", "ReloadUI", "geterrorhandler", "hooksecurefunc",
    "print", "wipe", "CopyTable",
}
globals = { "LKS_UI", "SlashCmdList", "SLASH_LKSUI1", "SLASH_LKSUI2" }
files[".tools/**"] = { std = "lua51", read_globals = {}, globals = {} }
