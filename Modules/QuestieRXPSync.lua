local _, ns = ...

local KEY = "QuestieRXPSync"
local SYNC_DELAY = 0.5
local WAIT_INTERVAL = 1
local WAIT_TRIES = 30
local DEFAULT_MAX_WATCHES = 25

local QUEST_TAGS = {
    accept = true, turnin = true, complete = true, collect = true,
    daily = true, dailyturnin = true, questgoto = true, questwaypoint = true,
}

local RXP_MESSAGES = { "RXP_GUIDE_LOADED", "RXP_STEP_ACTIVATED" }

local guide, guideQuests
local running = false
local pending = false
local fullSyncPending = false
local acceptedPending = {}
local hookedWindow
local questieTracker
local waiting = false
local warned = {}
local QueueSync

local function WarnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    ns.Print(msg)
end

local function GuideQuests(g)
    local quests = {}
    for index, step in ipairs(g.steps) do
        if type(step.elements) == "table" then
            for _, element in ipairs(step.elements) do
                local id = type(element) == "table" and QUEST_TAGS[element.tag] and tonumber(element.questId)
                if id and id > 0 then
                    local steps = quests[id] or {}
                    quests[id] = steps
                    if steps[#steps] ~= index then steps[#steps + 1] = index end
                end
            end
        end
    end
    return quests
end

local function IsTracked(questId)
    if questieTracker and questieTracker.IsTrackedByQuestie then
        return questieTracker.IsTrackedByQuestie(questId)
    end
    return C_QuestLog.GetQuestWatchType(questId) ~= nil
end

local function MaxWatches()
    local consts = _G.Constants and _G.Constants.QuestWatchConsts
    return consts and consts.MAX_QUEST_WATCHES or DEFAULT_MAX_WATCHES
end

local function WatchCount()
    return C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
end

local function CurrentStep()
    local data = _G.RXPCData
    return tonumber(data and data.currentStep) or 1
end

-- The guide's next step for this quest; quests whose steps all lie behind come last.
local function NextStep(steps, current)
    for _, index in ipairs(steps) do
        if index >= current then return index end
    end
    return math.huge
end

local function SetTracked(questId, track)
    local tracked = IsTracked(questId)
    if track and not tracked then
        C_QuestLog.AddQuestWatch(questId)
    elseif not track and tracked then
        C_QuestLog.RemoveQuestWatch(questId)
    end
end

local function OnGuideWindowShown()
    if guideQuests then fullSyncPending = true end
    QueueSync()
end

local function GuideOpen()
    local v2 = _G.RXPV2GuideWindow
    local v2Frame = type(v2) == "table" and v2.frame
    if v2Frame then
        if not hookedWindow then
            hookedWindow = true
            v2Frame:HookScript("OnShow", OnGuideWindowShown)
        end
        return v2Frame:IsVisible()
    end
    local frame = _G.RXPFrame
    return frame ~= nil and frame:IsVisible()
end

local function Sync()
    pending = false
    if not (running and guideQuests and GuideOpen()) then return end
    if fullSyncPending then
        fullSyncPending = false
        wipe(acceptedPending)
        local ids = {}
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            local id = info and not info.isHeader and info.questID
            if id and id > 0 then ids[#ids + 1] = id end
        end
        -- Untrack first so the watch limit has room for the guide's quests.
        for _, id in ipairs(ids) do
            if not guideQuests[id] then SetTracked(id, false) end
        end
        local current, wanted = CurrentStep(), {}
        for _, id in ipairs(ids) do
            if guideQuests[id] then wanted[#wanted + 1] = { id = id, step = NextStep(guideQuests[id], current) } end
        end
        table.sort(wanted, function(a, b)
            if a.step ~= b.step then return a.step < b.step end
            return a.id < b.id
        end)
        local max = MaxWatches()
        for _, q in ipairs(wanted) do
            if IsTracked(q.id) or WatchCount() < max then SetTracked(q.id, true) end
        end
    else
        for id in pairs(acceptedPending) do
            if C_QuestLog.GetLogIndexForQuestID(id) then
                if not guideQuests[id] then
                    SetTracked(id, false)
                elseif WatchCount() < MaxWatches() then
                    SetTracked(id, true)
                end
            end
        end
        wipe(acceptedPending)
    end
end

-- At login RestedXP sends its guide before the window is visible, and no OnShow follows, so poll for it.
local function WaitForWindow(tries)
    waiting = false
    if not (running and guideQuests and (fullSyncPending or next(acceptedPending))) then return end
    if GuideOpen() then
        QueueSync()
    elseif tries > 1 then
        waiting = true
        C_Timer.After(WAIT_INTERVAL, function() WaitForWindow(tries - 1) end)
    else
        WarnOnce("window", "RestedXP Quest Sync: no RestedXP guide window found; it syncs once the guide window opens.")
    end
end

QueueSync = function()
    if pending or not running or not guideQuests then return end
    if not (fullSyncPending or next(acceptedPending)) then return end
    if not GuideOpen() then
        if not waiting then
            waiting = true
            C_Timer.After(WAIT_INTERVAL, function() WaitForWindow(WAIT_TRIES) end)
        end
        return
    end
    pending = true
    C_Timer.After(SYNC_DELAY, Sync)
end

local function OnMessage(_, arg1, arg2)
    local g = arg2 or arg1
    if type(g) == "table" and type(g.steps) == "table" and g ~= guide then
        guide = g
        local quests = GuideQuests(g)
        if #g.steps > 0 and next(quests) == nil then
            guideQuests, fullSyncPending = nil, false
            wipe(acceptedPending)
            WarnOnce("format", "RestedXP Quest Sync: this guide section has no quests; waiting for the next one.")
        else
            guideQuests, fullSyncPending = quests, true
        end
    end
    QueueSync()
end

local function OnEvent(_, event, questId)
    if event == "QUEST_ACCEPTED" and type(questId) == "number" and questId > 0 then
        acceptedPending[questId] = true
        QueueSync()
    end
end

ns.RegisterFeature({
    key = KEY,
    title = "RestedXP Quest Sync",
    tab = "thirdparty",
    description = "Your quest tracker (Questie's, or the default one without Questie) shows the quests of your current RestedXP guide and untracks every other quest, on a guide switch, on each accepted quest and when the guide window opens. Changes nothing while the guide window is closed.",
    help = "Keeps your quest tracker on your current RestedXP guide: the guide's quests are tracked, every other quest is untracked. Works with Questie's tracker or, without Questie, the default quest tracker, which holds up to 25 quests; the guide's next quests come first. It runs while the RestedXP guide window is open, on login, when you switch guides and when you accept a quest. Turning it on or off needs a reload.",
    requires = { "RXPGuides" },
    optional = { "Questie" },
    enable = function()
        local AceEvent = _G.LibStub and _G.LibStub("AceEvent-3.0", true)
        if not AceEvent then return end
        local loader = _G.QuestieLoader
        questieTracker = loader and loader.ImportModule and loader:ImportModule("QuestieTracker")
        if loader and not (questieTracker and questieTracker.IsTrackedByQuestie) then
            WarnOnce("tracker", "RestedXP Quest Sync: Questie's tracker API changed; using the default tracker state.")
        end
        running = true
        local listener = {}
        AceEvent:Embed(listener)
        for _, message in ipairs(RXP_MESSAGES) do listener:RegisterMessage(message, OnMessage) end
        local events = CreateFrame("Frame")
        events:RegisterEvent("QUEST_ACCEPTED")
        events:SetScript("OnEvent", OnEvent)
        if _G.RXPFrame then _G.RXPFrame:HookScript("OnShow", OnGuideWindowShown) end
    end,
})
