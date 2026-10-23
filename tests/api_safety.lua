-- Run with Lua 5.1+ from the repository root. WoW secrets are approximated
-- by opaque sentinels; only an in-client test can validate real secret types.
local source = assert(io.open("EasyPreyProgress.lua", "r")):read("*a")
local secrets = setmetatable({}, { __mode = "k" })
local function secret()
    local value = setmetatable({}, {
        __index = function() error("secret indexed") end,
        __tostring = function() error("secret converted") end,
    })
    secrets[value] = true
    return value
end
issecretvalue = function(value) return secrets[value] == true end
SlashCmdList = {}
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local combat = false
InCombatLockdown = function() return combat end
local loadChunk = loadstring or load
local api = assert(loadChunk(source .. [[
return {
    number = safeToNumber, percent = extractProgressPercentFromInfo,
    trap = extractNearbyTrapText, warning = extractWarningStateFromText,
    objective = extractObjectivePercent, aura = hasPlayerAuraBySpellID,
    read = readPreyFieldsFromFrame, visibility = applyBlizzardWidgetVisibility,
    hook = ensurePreyWidgetHideHook, reset = resetTransientPreyState,
}
]], "EasyPreyProgress"))("EasyPreyProgress")
local opaque = secret()
assert(api.number(opaque) == nil)
assert(api.number("42") == 42)
assert(api.number(0/0) == nil)
assert(api.percent(opaque, opaque) == nil)
assert(api.percent({ percent = opaque, barValue = opaque, barMax = opaque }, opaque) == nil)
assert(api.percent({ percent = 0.42 }) == 42)
assert(api.percent({ barValue = 3, barMax = 4 }) == 75)
assert(api.trap(opaque) == nil and api.warning(opaque) == nil)
assert(api.trap("Nearby trap") == "Nearby trap")
assert(api.warning("Kill something!").type == "kill")
C_UnitAuras = { GetPlayerAuraBySpellID = function() return opaque end }
AuraUtil = { FindAuraBySpellID = function() error("legacy scan called") end }
assert(api.aura(123) == false)
C_UnitAuras.GetPlayerAuraBySpellID = function() return {} end
assert(api.aura(123) == true)
GetQuestProgressBarPercent = function() return opaque end
C_QuestLog = { GetQuestObjectives = function() return opaque end }
assert(api.objective(123) == nil)
C_QuestLog.GetQuestObjectives = function()
    return { opaque, { text = opaque, numFulfilled = opaque, numRequired = opaque } }
end
assert(api.objective(123) == nil)
C_QuestLog.GetQuestObjectives = function() return { { numFulfilled = 3, numRequired = 4 } } end
assert(api.objective(123) == 75)
assert(api.read({ progressState = opaque, tooltip = opaque, percent = opaque }) == nil)

local hooks, writes = 0, 0
local frame = {
    alpha = 0.6,
    PlayGainProgressAnim = function() end, PlayTransitionAnim = function() end,
    GetAlpha = function(self) return self.alpha end,
    SetAlpha = function(self, alpha) writes = writes + 1; self.alpha = alpha end,
    HookScript = function() hooks = hooks + 1 end,
}
local unrelated = { GetAlpha = function() error("unrelated widget touched") end }
UIWidgetPowerBarContainerFrame = {
    GetChildren = function() return frame, unrelated end,
    SetAlpha = function() error("shared container touched") end,
}
EasyPreyProgressDB = { hideBlizzardPreyWidget = true }
api.visibility()
assert(frame.alpha == 0 and hooks == 1)
api.reset()
api.visibility()
assert(hooks == 1, "duplicate OnShow hook after hunt reset")
EasyPreyProgressDB.hideBlizzardPreyWidget = false
api.visibility()
assert(frame.alpha == 0.6, "original alpha not restored")
combat = true
local before = writes
EasyPreyProgressDB.hideBlizzardPreyWidget = true
api.visibility()
assert(writes == before, "Blizzard frame modified during combat")
combat = false
frame.IsProtected = function() return true end
api.visibility()
assert(writes == before, "protected frame modified")
frame.IsForbidden = function() return true end
api.visibility()
assert(writes == before, "forbidden frame modified")
print("API safety regression checks passed")
