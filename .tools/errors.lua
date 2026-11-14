-- Usage: lua5.1 .tools/errors.lua <!BugGrabber.lua> <pattern> [--all-sessions]
local path, pattern, flag = arg[1], arg[2] or "LKS_UI", arg[3]

local chunk = assert(loadfile(path))
local env = {}
setfenv(chunk, env)
chunk()

local db = env.BugGrabberDB or {}
local session = db.session
local shown = 0
for _, e in ipairs(db.errors or {}) do
    local text = (e.message or "") .. "\n" .. (e.stack or "")
    local current = flag == "--all-sessions" or e.session == session
    if current and text:find(pattern, 1, true) then
        shown = shown + 1
        print(("--- x%d session %s %s"):format(e.counter or 1, tostring(e.session),
            os.date("!%Y-%m-%d %H:%M", e.time or 0)))
        print(e.message)
        if e.stack then print((e.stack:gsub("\n+$", ""))) end
    end
end
print(("%d error(s) matching %q in %s session %s"):format(shown, pattern,
    flag == "--all-sessions" and "every" or "the latest", tostring(session)))
