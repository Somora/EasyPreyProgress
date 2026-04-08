local addonName = ...

local addon = CreateFrame("Frame")
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("QUEST_ACCEPTED")
addon:RegisterEvent("QUEST_LOG_UPDATE")
addon:RegisterEvent("SUPER_TRACKING_CHANGED")
addon:RegisterEvent("ZONE_CHANGED")
addon:RegisterEvent("ZONE_CHANGED_INDOORS")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")

local PREY_PROGRESS_FINAL = 3
local MAX_STAGE = 4
local DEFAULTS = {
    point = { anchor = "CENTER", relativePoint = "CENTER", x = 0, y = 320 },
    width = 220,
    height = 20,
    locked = false,
    shown = true,
    onlyShowInPreyZone = true,
    hideBlizzardPreyWidget = true,
}

local STAGE_PERCENT = {
    [1] = 0,
    [2] = 33,
    [3] = 66,
    [4] = 100,
}

local STAGE_LABELS = {
    [1] = "Scent in the Wind",
    [2] = "Blood in the Shadows",
    [3] = "Echoes of the Kill",
    [4] = "Feast of the Fang",
}

local STAGE_COLORS = {
    [1] = { 0.78, 0.54, 0.22 },
    [2] = { 0.70, 0.26, 0.20 },
    [3] = { 0.56, 0.24, 0.62 },
    [4] = { 0.28, 0.64, 0.34 },
}

local STAGE_GLOSS_COLORS = {
    [1] = { 1.00, 0.90, 0.70, 0.16 },
    [2] = { 0.96, 0.84, 0.76, 0.13 },
    [3] = { 0.88, 0.82, 0.96, 0.14 },
    [4] = { 0.84, 0.95, 0.86, 0.14 },
}

local widgetHookInstalled = false
local preyWidgetCache = nil
local trackedPreyFrame = nil
local trackedPreyFrames = setmetatable({}, { __mode = "k" })
local trackedPreyVisualFrames = setmetatable({}, { __mode = "k" })
local debugEnabled = false
local hookedPreyFrames = setmetatable({}, { __mode = "k" })
local ensurePreyWidgetHideHook

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function getDB()
    EasyPreyProgressDB = EasyPreyProgressDB or {}
    mergeDefaults(EasyPreyProgressDB, DEFAULTS)
    return EasyPreyProgressDB
end

local function getActivePreyQuestID()
    if C_QuestLog and C_QuestLog.GetActivePreyQuest then
        return C_QuestLog.GetActivePreyQuest()
    end
    return nil
end

local function safeToNumber(value)
    local okString, asString = pcall(tostring, value)
    if not okString or type(asString) ~= "string" then
        return nil
    end

    local numericToken = string.match(asString, "^%s*([%+%-]?%d+%.?%d*)%s*$")
        or string.match(asString, "^%s*([%+%-]?%d*%.%d+)%s*$")
    if not numericToken then
        return nil
    end

    local okNumber, result = pcall(tonumber, numericToken)
    if okNumber and type(result) == "number" then
        return result
    end

    return nil
end

local MAP_ID_EQUIVALENTS = {
    [2437] = 2437,
    [2536] = 2437,
    [2413] = 2413,
    [2576] = 2413,
    [2405] = 2405,
    [2444] = 2405,
}

local QUEST_ZONE_MAP_OVERRIDES = {
    [91260] = 2437,
    [91106] = 2413,
    [91232] = 2413,
    [91233] = 2413,
}

local function canonicalizeMapID(mapID)
    mapID = safeToNumber(mapID)
    if not mapID or mapID < 1 then
        return nil
    end
    return MAP_ID_EQUIVALENTS[mapID] or mapID
end

local function isPlayerInPreyZone(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID or not C_QuestLog.GetInfo then
        return nil
    end

    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then
        return nil
    end

    local info = C_QuestLog.GetInfo(logIndex)
    if type(info) ~= "table" then
        return nil
    end

    if info.isOnMap == true then
        return true
    end

    local expectedMapID = canonicalizeMapID(QUEST_ZONE_MAP_OVERRIDES[questID])
    if expectedMapID == nil and C_TaskQuest and type(C_TaskQuest.GetQuestZoneID) == "function" then
        local okZoneMapID, rawZoneMapID = pcall(C_TaskQuest.GetQuestZoneID, questID)
        if okZoneMapID then
            expectedMapID = canonicalizeMapID(rawZoneMapID)
        end
    end

    if expectedMapID ~= nil and C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local okMapID, rawMapID = pcall(C_Map.GetBestMapForUnit, "player")
        local playerMapID = okMapID and canonicalizeMapID(rawMapID) or nil
        if playerMapID and playerMapID == expectedMapID then
            return true
        end
    end

    if info.isOnMap ~= nil then
        return info.isOnMap and true or false
    end

    return nil
end

local function getStageFromState(progressState)
    if progressState == PREY_PROGRESS_FINAL then
        return 4
    end
    if progressState == 2 then
        return 3
    end
    if progressState == 1 then
        return 2
    end
    return 1
end

local function isPreyHuntProgressFrame(frameRef)
    return frameRef
        and type(frameRef.ResetAnimState) == "function"
        and type(frameRef.AnimIn) == "function"
end

local function isLikelyPreyVisualFrame(frameRef)
    if not frameRef then
        return false
    end

    local name = nil
    if frameRef.GetName then
        local okName, resolvedName = pcall(frameRef.GetName, frameRef)
        if okName and type(resolvedName) == "string" then
            name = resolvedName
        end
    end
    if type(name) == "string" then
        local lowered = string.lower(name)
        if lowered:find("prey", 1, true) or lowered:find("hunt", 1, true) then
            return true
        end
        if lowered:find("icon", 1, true) or lowered:find("glow", 1, true) or lowered:find("pulse", 1, true) then
            return true
        end
    end

    if frameRef.effectController then
        return true
    end

    if frameRef.GetRegions then
        local okRegions, regions = pcall(function()
            return { frameRef:GetRegions() }
        end)
        if okRegions and type(regions) == "table" then
            for _, region in ipairs(regions) do
                local regionName = nil
                if region and region.GetName then
                    local okRegionName, resolvedRegionName = pcall(region.GetName, region)
                    if okRegionName and type(resolvedRegionName) == "string" then
                        regionName = resolvedRegionName
                    end
                end
                if type(regionName) == "string" then
                    local lowered = string.lower(regionName)
                    if lowered:find("prey", 1, true)
                        or lowered:find("hunt", 1, true)
                        or lowered:find("icon", 1, true)
                        or lowered:find("glow", 1, true)
                        or lowered:find("pulse", 1, true)
                    then
                        return true
                    end
                end
            end
        end
    end

    return false
end

ensurePreyWidgetHideHook = function(frameRef)
    if not frameRef or hookedPreyFrames[frameRef] or not frameRef.HookScript then
        return
    end

    hookedPreyFrames[frameRef] = true
    frameRef:HookScript("OnShow", function(self)
        if not getDB().hideBlizzardPreyWidget then
            return
        end

        if self.SetAlpha then
            pcall(self.SetAlpha, self, 0)
        end
        if self.Hide then
            pcall(self.Hide, self)
        end
    end)
end

local function captureLivePreyHuntFrames()
    local container = _G.UIWidgetPowerBarContainerFrame
    if not container or not container.GetChildren then
        return
    end

    local function scanFrameTree(frameRef, depth, visited)
        if not frameRef or (depth or 0) > 6 then
            return
        end

        visited = visited or {}
        if visited[frameRef] then
            return
        end
        visited[frameRef] = true

        if isPreyHuntProgressFrame(frameRef) then
            trackedPreyFrames[frameRef] = true
            trackedPreyFrame = frameRef
            ensurePreyWidgetHideHook(frameRef)
        elseif frameRef ~= container and isLikelyPreyVisualFrame(frameRef) then
            trackedPreyVisualFrames[frameRef] = true
            ensurePreyWidgetHideHook(frameRef)
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    scanFrameTree(child, (depth or 0) + 1, visited)
                end
            end
        end
    end

    scanFrameTree(container, 0, {})
end

local function applyBlizzardWidgetVisibility()
    local db = getDB()
    captureLivePreyHuntFrames()

    local function isLikelyAnimatedVisualRegion(region)
        if not region then
            return false
        end

        local objectType = region.GetObjectType and region:GetObjectType() or nil
        if objectType ~= "Texture" and objectType ~= "FontString" then
            return false
        end

        local regionName = nil
        if region.GetName then
            local okName, resolvedName = pcall(region.GetName, region)
            if okName and type(resolvedName) == "string" then
                regionName = resolvedName
            end
        end
        if type(regionName) ~= "string" then
            return false
        end

        local lowered = string.lower(regionName)
        return lowered:find("icon", 1, true) ~= nil
            or lowered:find("glow", 1, true) ~= nil
            or lowered:find("pulse", 1, true) ~= nil
            or lowered:find("flare", 1, true) ~= nil
    end

    local function stopFrameAnimations(frameRef, depth, visited)
        if not frameRef or (depth or 0) > 6 then
            return
        end

        visited = visited or {}
        if visited[frameRef] then
            return
        end
        visited[frameRef] = true

        if frameRef.GetAnimationGroups then
            local okGroups, groups = pcall(function()
                return { frameRef:GetAnimationGroups() }
            end)
            if okGroups and type(groups) == "table" then
                for _, group in ipairs(groups) do
                    if group and group.Stop then
                        pcall(group.Stop, group)
                    end
                end
            end
        end

        local commonAnimFields = {
            "AnimIn", "AnimOut", "GlowAnim", "PulseAnim", "Loop", "LoopingGlow", "Shine",
        }
        for _, fieldName in ipairs(commonAnimFields) do
            local candidate = frameRef[fieldName]
            if candidate and type(candidate) ~= "function" and candidate.Stop then
                pcall(candidate.Stop, candidate)
            end
        end

        if frameRef.GetRegions then
            local okRegions, regions = pcall(function()
                return { frameRef:GetRegions() }
            end)
            if okRegions and type(regions) == "table" then
                for _, region in ipairs(regions) do
                    if isLikelyAnimatedVisualRegion(region) then
                        if region.SetAlpha then
                            pcall(region.SetAlpha, region, 0)
                        end
                        if region.Hide then
                            pcall(region.Hide, region)
                        end
                    end
                end
            end
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    stopFrameAnimations(child, (depth or 0) + 1, visited)
                end
            end
        end
    end

    local function setRegionVisibility(frameRef, visible, depth, visited)
        if not frameRef or (depth or 0) > 6 then
            return
        end

        visited = visited or {}
        if visited[frameRef] then
            return
        end
        visited[frameRef] = true

        if frameRef.GetRegions then
            local okRegions, regions = pcall(function()
                return { frameRef:GetRegions() }
            end)
            if okRegions and type(regions) == "table" then
                for _, region in ipairs(regions) do
                    if region then
                        if visible then
                            if region.SetAlpha then
                                pcall(region.SetAlpha, region, 1)
                            end
                            if region.Show then
                                pcall(region.Show, region)
                            end
                        else
                            if region.SetAlpha then
                                pcall(region.SetAlpha, region, 0)
                            end
                            if region.Hide then
                                pcall(region.Hide, region)
                            end
                        end
                    end
                end
            end
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    setRegionVisibility(child, visible, (depth or 0) + 1, visited)
                    if visible then
                        if child.SetAlpha then
                            pcall(child.SetAlpha, child, 1)
                        end
                        if child.Show then
                            pcall(child.Show, child)
                        end
                    else
                        if child.SetAlpha then
                            pcall(child.SetAlpha, child, 0)
                        end
                        if child.Hide then
                            pcall(child.Hide, child)
                        end
                    end
                end
            end
        end
    end

    local function applyVisibility(frameRef)
        if db.hideBlizzardPreyWidget then
            stopFrameAnimations(frameRef, 0, {})
            setRegionVisibility(frameRef, false, 0, {})
            if frameRef.SetAlpha then
                pcall(frameRef.SetAlpha, frameRef, 0)
            end
            if frameRef.Hide then
                pcall(frameRef.Hide, frameRef)
            end
        else
            setRegionVisibility(frameRef, true, 0, {})
            if frameRef.SetAlpha then
                pcall(frameRef.SetAlpha, frameRef, 1)
            end
            if frameRef.Show then
                pcall(frameRef.Show, frameRef)
            end
        end
    end

    local function applyNamedSceneVisibility(frameName)
        local frameRef = _G[frameName]
        if not frameRef then
            return
        end

        if db.hideBlizzardPreyWidget then
            stopFrameAnimations(frameRef, 0, {})
            setRegionVisibility(frameRef, false, 0, {})
            if frameRef.SetAlpha then
                pcall(frameRef.SetAlpha, frameRef, 0)
            end
            if frameRef.Hide then
                pcall(frameRef.Hide, frameRef)
            end
        else
            setRegionVisibility(frameRef, true, 0, {})
            if frameRef.SetAlpha then
                pcall(frameRef.SetAlpha, frameRef, 1)
            end
            if frameRef.Show then
                pcall(frameRef.Show, frameRef)
            end
        end
    end

    for frameRef in pairs(trackedPreyFrames) do
        applyVisibility(frameRef)
    end

    for frameRef in pairs(trackedPreyVisualFrames) do
        applyVisibility(frameRef)
    end

    applyNamedSceneVisibility("UIWidgetBelowMinimapContainerFrame")
    applyNamedSceneVisibility("UIWidgetBelowMinimapContainerFrameFrontModelScene")
    applyNamedSceneVisibility("UIWidgetBelowMinimapContainerFrameBackModelScene")
    applyNamedSceneVisibility("UIWidgetPowerBarContainerFrame")
    applyNamedSceneVisibility("UIWidgetPowerBarContainerFrameFrontModelScene")
    applyNamedSceneVisibility("UIWidgetPowerBarContainerFrameBackModelScene")
end

local function extractProgressPercentFromInfo(info, tooltipText)
    if type(info) == "table" then
        local directFields = {
            "progressPercentage",
            "progressPercent",
            "fillPercentage",
            "percentage",
            "percent",
            "progress",
            "progressValue",
        }

        for _, fieldName in ipairs(directFields) do
            local value = info[fieldName]
            if type(value) == "number" then
                if value >= 0 and value <= 1 then
                    return clamp(value * 100, 0, 100)
                end
                return clamp(value, 0, 100)
            end
        end

        local current = info.barValue or info.value or info.currentValue
        local maximum = info.barMax or info.maxValue or info.totalValue or info.total or info.max
        if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
            return clamp((current / maximum) * 100, 0, 100)
        end

        for key, value in pairs(info) do
            if type(value) == "number" then
                local lowered = string.lower(tostring(key))
                if lowered:find("percent", 1, true) then
                    if value >= 0 and value <= 1 then
                        return clamp(value * 100, 0, 100)
                    end
                    return clamp(value, 0, 100)
                end
            end
        end
    end

    if type(tooltipText) == "string" then
        local pct = tonumber(tooltipText:match("(%d+)%s*%%"))
        if pct then
            return clamp(pct, 0, 100)
        end
    end

    return nil
end

local function extractNearbyTrapText(tooltipText)
    if type(tooltipText) ~= "string" or tooltipText == "" then
        return nil
    end

    for line in string.gmatch(tooltipText, "[^\r\n]+") do
        local lowered = string.lower(line)
        if lowered:find("trap", 1, true) then
            return line:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end

    return nil
end

local function sanitizeStageDescription(text)
    if type(text) ~= "string" then
        return nil
    end

    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return nil
    end

    local lowered = cleaned:lower()
    if lowered:find("trap", 1, true) then
        return nil
    end
    if lowered:find("nearby", 1, true) then
        return nil
    end
    if lowered:find("complete prey activities", 1, true) then
        return nil
    end
    if lowered:find("draw closer to your prey", 1, true) then
        return nil
    end
    if lowered:find("^stage%s*:?%s*%d", 1) then
        return nil
    end

    return cleaned
end

local function extractStageDescriptionFromTooltip(tooltipText)
    if type(tooltipText) ~= "string" or tooltipText == "" then
        return nil
    end

    for line in string.gmatch(tooltipText, "[^\r\n]+") do
        local cleaned = sanitizeStageDescription(line)
        if cleaned then
            return cleaned
        end
    end

    return nil
end

local function extractTrapTextFromObjectives(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then
        return nil
    end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" then
        return nil
    end

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" and type(objective.text) == "string" then
            local text = objective.text:gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" and text:lower():find("trap", 1, true) then
                return text
            end
        end
    end

    return nil
end

local function extractStageDescriptionFromObjectives(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then
        return nil
    end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" then
        return nil
    end

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" and type(objective.text) == "string" then
            local cleaned = sanitizeStageDescription(objective.text)
            if cleaned then
                return cleaned
            end
        end
    end

    return nil
end

local function collectTrapTextFromRegionOwner(owner)
    if not owner then
        return nil
    end

    local function scanRegions(container)
        if not container or not container.GetRegions then
            return nil
        end

        local okRegions, regions = pcall(function()
            return { container:GetRegions() }
        end)
        if not okRegions or type(regions) ~= "table" then
            return nil
        end

        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                local okText, text = pcall(region.GetText, region)
                if okText and type(text) == "string" and text ~= "" and text:lower():find("trap", 1, true) then
                    return text:gsub("^%s+", ""):gsub("%s+$", "")
                end
            end
        end

        return nil
    end

    local direct = scanRegions(owner)
    if direct then
        return direct
    end

    if owner.GetChildren then
        local okChildren, children = pcall(function()
            return { owner:GetChildren() }
        end)
        if okChildren and type(children) == "table" then
            for _, child in ipairs(children) do
                local childText = scanRegions(child)
                if childText then
                    return childText
                end
            end
        end
    end

    return nil
end

local function extractTrapTextFromWidgetFrame()
    if trackedPreyFrame then
        local text = collectTrapTextFromRegionOwner(trackedPreyFrame)
        if text then
            return text
        end
    end

    for frameRef in pairs(trackedPreyFrames) do
        local text = collectTrapTextFromRegionOwner(frameRef)
        if text then
            trackedPreyFrame = frameRef
            return text
        end
    end

    return nil
end

local function collectStageDescriptionFromRegionOwner(owner)
    if not owner then
        return nil
    end

    local function scanRegions(container)
        if not container or not container.GetRegions then
            return nil
        end

        local okRegions, regions = pcall(function()
            return { container:GetRegions() }
        end)
        if not okRegions or type(regions) ~= "table" then
            return nil
        end

        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                local okText, text = pcall(region.GetText, region)
                if okText then
                    local cleaned = sanitizeStageDescription(text)
                    if cleaned then
                        return cleaned
                    end
                end
            end
        end

        return nil
    end

    local direct = scanRegions(owner)
    if direct then
        return direct
    end

    if owner.GetChildren then
        local okChildren, children = pcall(function()
            return { owner:GetChildren() }
        end)
        if okChildren and type(children) == "table" then
            for _, child in ipairs(children) do
                local childText = scanRegions(child)
                if childText then
                    return childText
                end
            end
        end
    end

    return nil
end

local function extractStageDescriptionFromWidgetFrame()
    if trackedPreyFrame then
        local text = collectStageDescriptionFromRegionOwner(trackedPreyFrame)
        if text then
            return text
        end
    end

    for frameRef in pairs(trackedPreyFrames) do
        local text = collectStageDescriptionFromRegionOwner(frameRef)
        if text then
            trackedPreyFrame = frameRef
            return text
        end
    end

    return nil
end

local function debugSafeName(obj)
    if not obj or not obj.GetName then
        return nil
    end

    local okName, name = pcall(obj.GetName, obj)
    if okName and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function debugSafeObjectType(obj)
    if not obj or not obj.GetObjectType then
        return nil
    end

    local okType, objectType = pcall(obj.GetObjectType, obj)
    if okType and type(objectType) == "string" then
        return objectType
    end
    return nil
end

local function printTrackedPreyFrameTree()
    captureLivePreyHuntFrames()

    local function printLine(prefix, obj)
        local name = debugSafeName(obj) or "<unnamed>"
        local objectType = debugSafeObjectType(obj) or type(obj)
        local shown = obj and obj.IsShown and obj:IsShown() and "shown" or "hidden"
        print(string.format("|cffd6a800EasyPreyProgress|r %s%s [%s, %s]", prefix, name, objectType, shown))
    end

    local function walk(frameRef, depth, visited)
        if not frameRef or (depth or 0) > 4 then
            return
        end

        visited = visited or {}
        if visited[frameRef] then
            return
        end
        visited[frameRef] = true

        local prefix = string.rep("  ", depth or 0)
        printLine(prefix, frameRef)

        if frameRef.GetRegions then
            local okRegions, regions = pcall(function()
                return { frameRef:GetRegions() }
            end)
            if okRegions and type(regions) == "table" then
                for _, region in ipairs(regions) do
                    local regionName = debugSafeName(region)
                    local objectType = debugSafeObjectType(region)
                    if regionName or objectType == "Texture" or objectType == "FontString" then
                        printLine(prefix .. "  - ", region)
                    end
                end
            end
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    walk(child, (depth or 0) + 1, visited)
                end
            end
        end
    end

    local foundAny = false
    for frameRef in pairs(trackedPreyFrames) do
        foundAny = true
        walk(frameRef, 0, {})
    end
    for frameRef in pairs(trackedPreyVisualFrames) do
        foundAny = true
        walk(frameRef, 0, {})
    end

    if not foundAny then
        print("|cffd6a800EasyPreyProgress|r no tracked prey frames found")
    end
end

local function printVisibleUiFrames()
    local root = _G.UIParent
    if not root or not root.GetChildren then
        print("|cffd6a800EasyPreyProgress|r UIParent not available")
        return
    end

    local function safeShown(obj)
        if not obj or not obj.IsShown then
            return false
        end
        local okShown, shown = pcall(obj.IsShown, obj)
        return okShown and shown == true
    end

    local function safeSize(obj)
        if not obj or not obj.GetSize then
            return nil, nil
        end
        local okSize, w, h = pcall(obj.GetSize, obj)
        if okSize then
            return w, h
        end
        return nil, nil
    end

    local seen = {}
    local function walk(frameRef, depth)
        if not frameRef or depth > 3 or seen[frameRef] then
            return
        end
        seen[frameRef] = true

        if safeShown(frameRef) then
            local name = debugSafeName(frameRef) or "<unnamed>"
            local objectType = debugSafeObjectType(frameRef) or type(frameRef)
            local w, h = safeSize(frameRef)
            print(string.format("|cffd6a800EasyPreyProgress visible|r %s [%s, %.0fx%.0f]", name, objectType, w or 0, h or 0))
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    walk(child, depth + 1)
                end
            end
        end
    end

    walk(root, 0)
end

local function printVisibleUiIcons()
    local root = _G.UIParent
    if not root or not root.GetChildren then
        print("|cffd6a800EasyPreyProgress|r UIParent not available")
        return
    end

    local function safeShown(obj)
        if not obj or not obj.IsShown then
            return false
        end
        local okShown, shown = pcall(obj.IsShown, obj)
        return okShown and shown == true
    end

    local function safeSize(obj)
        if not obj or not obj.GetSize then
            return nil, nil
        end
        local okSize, w, h = pcall(obj.GetSize, obj)
        if okSize then
            return w, h
        end
        return nil, nil
    end

    local function safeCenter(obj)
        if not obj or not obj.GetCenter then
            return nil, nil
        end
        local okCenter, x, y = pcall(obj.GetCenter, obj)
        if okCenter then
            return x, y
        end
        return nil, nil
    end

    local function firstRegionSummary(frameRef)
        if not frameRef or not frameRef.GetRegions then
            return nil
        end
        local okRegions, regions = pcall(function()
            return { frameRef:GetRegions() }
        end)
        if not okRegions or type(regions) ~= "table" then
            return nil
        end

        for _, region in ipairs(regions) do
            local objectType = debugSafeObjectType(region)
            if objectType == "Texture" then
                local regionName = debugSafeName(region) or "<unnamed>"
                local atlas = nil
                if region.GetAtlas then
                    local okAtlas, resolvedAtlas = pcall(region.GetAtlas, region)
                    if okAtlas and type(resolvedAtlas) == "string" and resolvedAtlas ~= "" then
                        atlas = resolvedAtlas
                    end
                end
                local texture = nil
                if region.GetTexture then
                    local okTexture, resolvedTexture = pcall(region.GetTexture, region)
                    if okTexture and resolvedTexture then
                        texture = tostring(resolvedTexture)
                    end
                end
                return string.format("%s atlas=%s texture=%s", regionName, atlas or "-", texture or "-")
            end
        end

        return nil
    end

    local seen = {}
    local matches = 0
    local function walk(frameRef, depth)
        if not frameRef or depth > 4 or seen[frameRef] then
            return
        end
        seen[frameRef] = true

        local objectType = debugSafeObjectType(frameRef)
        local name = debugSafeName(frameRef)
        local w, h = safeSize(frameRef)
        local x, y = safeCenter(frameRef)

        local smallEnough = (w and h and w > 0 and h > 0 and w <= 120 and h <= 120)
        local unnamed = name == nil
        local interestingType = objectType == "Button" or objectType == "Frame"
        if interestingType and unnamed and smallEnough and safeShown(frameRef) then
            matches = matches + 1
            print(string.format(
                "|cffd6a800EasyPreyProgress icon|r #%d <unnamed> [%s, %.0fx%.0f, center=%.0f,%.0f] %s",
                matches,
                objectType or "?",
                w or 0,
                h or 0,
                x or 0,
                y or 0,
                firstRegionSummary(frameRef) or "no texture summary"
            ))
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    walk(child, depth + 1)
                end
            end
        end
    end

    walk(root, 0)
    if matches == 0 then
        print("|cffd6a800EasyPreyProgress|r no matching visible icon frames found")
    end
end

local function printVisibleFramesNearCursor()
    local root = _G.UIParent
    local cursorX, cursorY = _G.GetCursorPosition()
    if not root or not root.GetChildren or not cursorX or not cursorY then
        print("|cffd6a800EasyPreyProgress|r cursor inspection unavailable")
        return
    end

    local rootScale = (root.GetEffectiveScale and root:GetEffectiveScale()) or 1
    cursorX = cursorX / rootScale
    cursorY = cursorY / rootScale

    local function safeShown(obj)
        if not obj or not obj.IsShown then
            return false
        end
        local okShown, shown = pcall(obj.IsShown, obj)
        return okShown and shown == true
    end

    local function safeRect(obj)
        if not obj or not obj.GetLeft or not obj.GetRight or not obj.GetTop or not obj.GetBottom then
            return nil, nil, nil, nil
        end
        local okLeft, left = pcall(obj.GetLeft, obj)
        local okRight, right = pcall(obj.GetRight, obj)
        local okTop, top = pcall(obj.GetTop, obj)
        local okBottom, bottom = pcall(obj.GetBottom, obj)
        if okLeft and okRight and okTop and okBottom then
            return left, right, top, bottom
        end
        return nil, nil, nil, nil
    end

    local function firstRegionSummary(frameRef)
        if not frameRef or not frameRef.GetRegions then
            return nil
        end
        local okRegions, regions = pcall(function()
            return { frameRef:GetRegions() }
        end)
        if not okRegions or type(regions) ~= "table" then
            return nil
        end

        for _, region in ipairs(regions) do
            local objectType = debugSafeObjectType(region)
            if objectType == "Texture" then
                local atlas = nil
                if region.GetAtlas then
                    local okAtlas, resolvedAtlas = pcall(region.GetAtlas, region)
                    if okAtlas and type(resolvedAtlas) == "string" and resolvedAtlas ~= "" then
                        atlas = resolvedAtlas
                    end
                end
                local texture = nil
                if region.GetTexture then
                    local okTexture, resolvedTexture = pcall(region.GetTexture, region)
                    if okTexture and resolvedTexture then
                        texture = tostring(resolvedTexture)
                    end
                end
                return string.format("atlas=%s texture=%s", atlas or "-", texture or "-")
            end
        end

        return "no texture summary"
    end

    local seen = {}
    local matches = 0
    local function walk(frameRef, depth)
        if not frameRef or depth > 4 or seen[frameRef] then
            return
        end
        seen[frameRef] = true

        if safeShown(frameRef) then
            local left, right, top, bottom = safeRect(frameRef)
            if left and right and top and bottom
                and cursorX >= left and cursorX <= right
                and cursorY >= bottom and cursorY <= top
            then
                matches = matches + 1
                local name = debugSafeName(frameRef) or "<unnamed>"
                local objectType = debugSafeObjectType(frameRef) or type(frameRef)
                print(string.format(
                    "|cffd6a800EasyPreyProgress cursor|r #%d %s [%s] %s",
                    matches,
                    name,
                    objectType,
                    firstRegionSummary(frameRef)
                ))
            end
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    walk(child, depth + 1)
                end
            end
        end
    end

    walk(root, 0)
    if matches == 0 then
        print("|cffd6a800EasyPreyProgress|r no visible frames under cursor")
    end
end

local function printTimerTrackerTree()
    local tracker = _G.TimerTracker
    if not tracker then
        print("|cffd6a800EasyPreyProgress|r TimerTracker not found")
        return
    end

    local function safeShown(obj)
        if not obj or not obj.IsShown then
            return false
        end
        local okShown, shown = pcall(obj.IsShown, obj)
        return okShown and shown == true
    end

    local function firstRegionSummary(frameRef)
        if not frameRef or not frameRef.GetRegions then
            return "no texture summary"
        end
        local okRegions, regions = pcall(function()
            return { frameRef:GetRegions() }
        end)
        if not okRegions or type(regions) ~= "table" then
            return "no texture summary"
        end

        for _, region in ipairs(regions) do
            local objectType = debugSafeObjectType(region)
            if objectType == "Texture" then
                local atlas = nil
                if region.GetAtlas then
                    local okAtlas, resolvedAtlas = pcall(region.GetAtlas, region)
                    if okAtlas and type(resolvedAtlas) == "string" and resolvedAtlas ~= "" then
                        atlas = resolvedAtlas
                    end
                end
                local texture = nil
                if region.GetTexture then
                    local okTexture, resolvedTexture = pcall(region.GetTexture, region)
                    if okTexture and resolvedTexture then
                        texture = tostring(resolvedTexture)
                    end
                end
                return string.format("atlas=%s texture=%s", atlas or "-", texture or "-")
            end
        end

        return "no texture summary"
    end

    local seen = {}
    local function walk(frameRef, depth)
        if not frameRef or depth > 5 or seen[frameRef] then
            return
        end
        seen[frameRef] = true

        local prefix = string.rep("  ", depth)
        local name = debugSafeName(frameRef) or "<unnamed>"
        local objectType = debugSafeObjectType(frameRef) or type(frameRef)
        local shown = safeShown(frameRef) and "shown" or "hidden"
        print(string.format("|cffd6a800EasyPreyProgress timer|r %s%s [%s, %s] %s", prefix, name, objectType, shown, firstRegionSummary(frameRef)))

        if frameRef.GetRegions then
            local okRegions, regions = pcall(function()
                return { frameRef:GetRegions() }
            end)
            if okRegions and type(regions) == "table" then
                for _, region in ipairs(regions) do
                    local regionName = debugSafeName(region) or "<unnamed>"
                    local regionType = debugSafeObjectType(region) or type(region)
                    local summary = "no texture summary"
                    if regionType == "Texture" then
                        local atlas = nil
                        if region.GetAtlas then
                            local okAtlas, resolvedAtlas = pcall(region.GetAtlas, region)
                            if okAtlas and type(resolvedAtlas) == "string" and resolvedAtlas ~= "" then
                                atlas = resolvedAtlas
                            end
                        end
                        local texture = nil
                        if region.GetTexture then
                            local okTexture, resolvedTexture = pcall(region.GetTexture, region)
                            if okTexture and resolvedTexture then
                                texture = tostring(resolvedTexture)
                            end
                        end
                        summary = string.format("atlas=%s texture=%s", atlas or "-", texture or "-")
                    end
                    print(string.format("|cffd6a800EasyPreyProgress timer|r %s  - %s [%s] %s", prefix, regionName, regionType, summary))
                end
            end
        end

        if frameRef.GetChildren then
            local okChildren, children = pcall(function()
                return { frameRef:GetChildren() }
            end)
            if okChildren and type(children) == "table" then
                for _, child in ipairs(children) do
                    walk(child, depth + 1)
                end
            end
        end
    end

    walk(tracker, 0)
end

local function readPreyFieldsFromFrame(frameRef)
    if type(frameRef) ~= "table" then
        return nil
    end

    local function readValue(obj, keyName)
        if type(obj) ~= "table" then
            return nil
        end

        local okDirect, directValue = pcall(function()
            return obj[keyName]
        end)
        if okDirect and directValue ~= nil then
            return directValue
        end

        local getterName = "Get" .. string.upper(string.sub(keyName, 1, 1)) .. string.sub(keyName, 2)
        local okGetter, getter = pcall(function()
            return obj[getterName]
        end)
        if okGetter and type(getter) == "function" then
            local okCall, value = pcall(getter, obj)
            if okCall and value ~= nil then
                return value
            end
        end

        return nil
    end

    local candidates = {
        { value = frameRef, source = "frame" },
        { value = readValue(frameRef, "widgetInfo"), source = "frame.widgetInfo" },
        { value = readValue(frameRef, "widgetData"), source = "frame.widgetData" },
        { value = readValue(frameRef, "dataSource"), source = "frame.dataSource" },
        { value = readValue(frameRef, "info"), source = "frame.info" },
    }

    for _, candidate in ipairs(candidates) do
        local value = candidate.value
        if type(value) == "table" then
            local progressState = readValue(value, "progressState")
            local tooltipText = readValue(value, "tooltip")
            if type(tooltipText) ~= "string" then
                tooltipText = nil
            end
            local percent = extractProgressPercentFromInfo(value, tooltipText)
            if progressState ~= nil or tooltipText ~= nil or percent ~= nil then
                return {
                    progressState = progressState,
                    tooltip = tooltipText,
                    percent = percent,
                    source = candidate.source,
                }
            end
        end
    end

    return nil
end

local function installPreyWidgetHook()
    if widgetHookInstalled or type(hooksecurefunc) ~= "function" then
        return
    end

    local mixin = _G.UIWidgetTemplatePreyHuntProgressMixin
    if not mixin then
        return
    end

    local ok = pcall(hooksecurefunc, mixin, "Setup", function(self, widgetInfo)
        trackedPreyFrame = self
        trackedPreyFrames[self] = true

        local tooltipText = type(widgetInfo) == "table" and type(widgetInfo.tooltip) == "string" and widgetInfo.tooltip or nil
        local progressState = type(widgetInfo) == "table" and widgetInfo.progressState or nil
        local percent = extractProgressPercentFromInfo(widgetInfo, tooltipText)
        local source = "widgetInfo"

        if progressState == nil or tooltipText == nil or percent == nil then
            local frameData = readPreyFieldsFromFrame(self)
            if frameData then
                progressState = progressState or frameData.progressState
                tooltipText = tooltipText or frameData.tooltip
                percent = percent or frameData.percent
                source = frameData.source or source
            end
        end

        preyWidgetCache = {
            progressState = progressState,
            tooltip = tooltipText,
            percent = percent,
            seenAt = GetTime and GetTime() or 0,
            source = source,
        }

        applyBlizzardWidgetVisibility()
    end)

    if ok then
        widgetHookInstalled = true
        captureLivePreyHuntFrames()
        applyBlizzardWidgetVisibility()
    end
end

local function refreshWidgetCacheFromFrame()
    captureLivePreyHuntFrames()

    local frameData = trackedPreyFrame and readPreyFieldsFromFrame(trackedPreyFrame) or nil
    if not frameData then
        for frameRef in pairs(trackedPreyFrames) do
            frameData = readPreyFieldsFromFrame(frameRef)
            if frameData then
                trackedPreyFrame = frameRef
                break
            end
        end
    end

    if not frameData then
        return
    end

    preyWidgetCache = {
        progressState = frameData.progressState,
        tooltip = frameData.tooltip,
        percent = frameData.percent,
        seenAt = GetTime and GetTime() or 0,
        source = frameData.source,
    }
end

local function extractObjectivePercent(questID)
    if not questID then
        return nil
    end

    local questBarPct
    if GetQuestProgressBarPercent then
        local ok, value = pcall(GetQuestProgressBarPercent, questID)
        if ok and type(value) == "number" then
            questBarPct = clamp(value, 0, 100)
        end
    end

    if not C_QuestLog or not C_QuestLog.GetQuestObjectives then
        return questBarPct
    end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" then
        return questBarPct
    end

    local totalFulfilled = 0
    local totalRequired = 0
    local foundNumeric = false

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            local fulfilled = tonumber(objective.numFulfilled or objective.fulfilled)
            local required = tonumber(objective.numRequired or objective.required)

            if fulfilled ~= nil and required ~= nil and required > 0 then
                totalFulfilled = totalFulfilled + math.max(0, fulfilled)
                totalRequired = totalRequired + math.max(0, required)
                foundNumeric = true
            elseif type(objective.text) == "string" then
                local current, maximum = objective.text:match("(%d+)%s*/%s*(%d+)")
                current = tonumber(current)
                maximum = tonumber(maximum)
                if current and maximum and maximum > 0 then
                    totalFulfilled = totalFulfilled + current
                    totalRequired = totalRequired + maximum
                    foundNumeric = true
                else
                    local pct = tonumber(objective.text:match("(%d+)%s*%%"))
                    if pct then
                        return clamp(pct, 0, 100)
                    end
                end
            end
        end
    end

    local objectivePct
    if foundNumeric and totalRequired > 0 then
        objectivePct = clamp((totalFulfilled / totalRequired) * 100, 0, 100)
    end

    if objectivePct and questBarPct then
        return math.max(objectivePct, questBarPct)
    end

    return objectivePct or questBarPct
end

local function getPreyProgress()
    local questID = getActivePreyQuestID()
    if not questID then
        return nil
    end

    local stage = 1
    local percent = nil
    local source = "fallback"

    refreshWidgetCacheFromFrame()

    if preyWidgetCache and ((GetTime and GetTime() or 0) - (preyWidgetCache.seenAt or 0)) <= 3 then
        if preyWidgetCache.progressState ~= nil then
            stage = getStageFromState(preyWidgetCache.progressState)
            source = preyWidgetCache.source or "widget"
        end
        if preyWidgetCache.percent ~= nil then
            percent = preyWidgetCache.percent
            source = preyWidgetCache.source or "widget"
        end
    end

    if percent == nil and not (preyWidgetCache and preyWidgetCache.progressState ~= nil) then
        percent = extractObjectivePercent(questID)
        if percent ~= nil then
            source = "objective"
        end
    end

    if percent == nil then
        local progressState = preyWidgetCache and preyWidgetCache.progressState or nil
        if progressState == nil and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) then
            progressState = PREY_PROGRESS_FINAL
        end
        stage = getStageFromState(progressState)
        percent = STAGE_PERCENT[stage]
        source = progressState ~= nil and (preyWidgetCache and preyWidgetCache.source or "stage") or "fallback"
    elseif preyWidgetCache == nil or preyWidgetCache.progressState == nil then
        stage = clamp(math.ceil(percent / 25), 1, MAX_STAGE)
    end

    return {
        questID = questID,
        percent = clamp(percent, 0, 100),
        stage = stage,
        source = source,
        inPreyZone = isPlayerInPreyZone(questID),
        nearbyTrapText = (preyWidgetCache and extractNearbyTrapText(preyWidgetCache.tooltip))
            or extractTrapTextFromWidgetFrame()
            or extractTrapTextFromObjectives(questID),
    }
end

local function createUI()
    if addon.frame then
        return
    end

    local db = getDB()

    local frame = CreateFrame("Frame", "EasyPreyProgressFrame", UIParent, "BackdropTemplate")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.02, 0.02, 0.03, 0.78)
    frame:SetBackdropBorderColor(0.58, 0.46, 0.20, 0.95)

    local panelShade = frame:CreateTexture(nil, "BACKGROUND")
    panelShade:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
    panelShade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
    panelShade:SetColorTexture(0.09, 0.08, 0.06, 0.35)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText("Prey Progress")
    title:SetTextColor(0.94, 0.78, 0.28, 0.96)

    local barShell = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    barShell:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -22)
    barShell:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -22)
    barShell:SetHeight(db.height)
    barShell:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    barShell:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
    barShell:SetBackdropBorderColor(0.36, 0.28, 0.12, 0.95)

    local bar = CreateFrame("StatusBar", nil, barShell)
    bar:SetPoint("TOPLEFT", barShell, "TOPLEFT", 5, -5)
    bar:SetPoint("BOTTOMRIGHT", barShell, "BOTTOMRIGHT", -5, 5)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:GetStatusBarTexture():SetHorizTile(false)
    bar:GetStatusBarTexture():SetVertTile(false)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.84, 0.2, 0.2, 0.95)

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.10, 0.06, 0.06, 0.92)

    local barUnderGlow = bar:CreateTexture(nil, "ARTWORK")
    barUnderGlow:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
    barUnderGlow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 2)
    barUnderGlow:SetColorTexture(0.40, 0.10, 0.10, 0.18)

    local barGloss = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    barGloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, -2)
    barGloss:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -2, -2)
    barGloss:SetHeight(math.max(4, math.floor(db.height * 0.45)))
    barGloss:SetColorTexture(1, 0.95, 0.85, 0.10)

    local barInnerLine = bar:CreateTexture(nil, "OVERLAY")
    barInnerLine:SetHeight(1)
    barInnerLine:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, -3)
    barInnerLine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, -3)
    barInnerLine:SetColorTexture(1, 0.95, 0.80, 0.18)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 0.96, 0.88, 1)

    local stageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stageText:SetPoint("TOP", barShell, "BOTTOM", 0, -8)
    stageText:SetTextColor(0.86, 0.78, 0.58, 0.92)
    stageText:SetWidth(math.max(120, db.width - 28))
    stageText:SetJustifyH("CENTER")

    local trapText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    trapText:SetPoint("TOP", stageText, "BOTTOM", 0, -4)
    trapText:SetTextColor(0.82, 0.68, 0.30, 0.88)
    trapText:SetWidth(math.max(120, db.width - 28))
    trapText:SetJustifyH("CENTER")

    frame:SetScript("OnDragStart", function(self)
        if getDB().locked then
            return
        end
        if not IsShiftKeyDown or not IsShiftKeyDown() then
            return
        end
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        local currentDB = getDB()
        currentDB.point.anchor = point
        currentDB.point.relativePoint = relativePoint
        currentDB.point.x = math.floor(x + 0.5)
        currentDB.point.y = math.floor(y + 0.5)
    end)

    addon.frame = frame
    addon.title = title
    addon.barShell = barShell
    addon.bar = bar
    addon.barUnderGlow = barUnderGlow
    addon.barGloss = barGloss
    addon.barInnerLine = barInnerLine
    addon.text = text
    addon.stageText = stageText
    addon.trapText = trapText

    local titleFont, _, titleFlags = title:GetFont()
    title:SetFont(titleFont, 11, titleFlags)
end

local function applyLayout()
    local db = getDB()
    addon.frame:ClearAllPoints()
    addon.frame:SetPoint(db.point.anchor, UIParent, db.point.relativePoint, db.point.x, db.point.y)
    addon.frame:SetSize(db.width, db.height + 62)
    addon.barShell:SetHeight(db.height)
    addon.stageText:SetWidth(math.max(120, db.width - 28))
    addon.trapText:SetWidth(math.max(120, db.width - 28))
    if addon.barGloss then
        addon.barGloss:SetHeight(math.max(4, math.floor((db.height - 6) * 0.45)))
    end
    addon.frame:SetShown(db.shown)
    if db.locked then
        addon.frame:SetBackdropBorderColor(0.56, 0.43, 0.18, 0.92)
    else
        addon.frame:SetBackdropBorderColor(0.82, 0.70, 0.32, 0.98)
    end

    applyBlizzardWidgetVisibility()
end

function addon:Refresh()
    if not self.frame then
        return
    end

    local progress = getPreyProgress()
    if not progress then
        self.bar:SetValue(0)
        self.text:SetText("Geen actieve Prey")
        self.stageText:SetText("Wacht op een actieve prey quest")
        self.frame:Hide()
        return
    end

    local db = getDB()
    if not db.shown then
        self.frame:Hide()
        return
    end

    local hasRecentWidgetSignal = preyWidgetCache
        and ((GetTime and GetTime() or 0) - (preyWidgetCache.seenAt or 0)) <= 3
        and (preyWidgetCache.progressState ~= nil or preyWidgetCache.percent ~= nil)

    if db.onlyShowInPreyZone and progress.inPreyZone == false and not hasRecentWidgetSignal then
        self.frame:Hide()
        return
    end

    self.frame:Show()
    self.bar:SetValue(progress.percent)
    local stageColor = STAGE_COLORS[progress.stage] or STAGE_COLORS[1]
    local glossColor = STAGE_GLOSS_COLORS[progress.stage] or STAGE_GLOSS_COLORS[1]
    self.bar:SetStatusBarColor(stageColor[1], stageColor[2], stageColor[3], 0.95)
    if self.barUnderGlow then
        self.barUnderGlow:SetColorTexture(stageColor[1], stageColor[2], stageColor[3], 0.16)
    end
    if self.barGloss then
        self.barGloss:SetColorTexture(glossColor[1], glossColor[2], glossColor[3], glossColor[4])
    end
    self.text:SetFormattedText("%d%%", progress.percent)
    self.stageText:SetFontObject("GameFontNormalSmall")
    local stageLine
    if debugEnabled then
        stageLine = string.format("Stage %d/4 [%s]", progress.stage, progress.source or "?")
    else
        stageLine = string.format("Stage %d/4", progress.stage)
    end

    self.stageText:SetText(stageLine)
    if self.stageText:GetStringWidth() > (self.stageText:GetWidth() + 4) then
        self.stageText:SetFontObject("GameFontDisableSmall")
        self.stageText:SetText(stageLine)
    end

    if progress.nearbyTrapText and progress.nearbyTrapText ~= "" then
        self.trapText:SetText(progress.nearbyTrapText)
        self.trapText:Show()
    else
        self.trapText:SetText("")
        self.trapText:Hide()
    end
end

SLASH_EASYPREYPROGRESS1 = "/epp"
SlashCmdList.EASYPREYPROGRESS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local db = getDB()

    if msg == "lock" then
        db.locked = true
    elseif msg == "unlock" then
        db.locked = false
    elseif msg == "hide" then
        db.shown = false
    elseif msg == "show" then
        db.shown = true
    elseif msg == "reset" then
        EasyPreyProgressDB = {}
        db = getDB()
    elseif msg == "zone" then
        db.onlyShowInPreyZone = not db.onlyShowInPreyZone
        print("|cffd6a800EasyPreyProgress|r alleen in prey-zone: " .. (db.onlyShowInPreyZone and "aan" or "uit"))
    elseif msg == "blizz" then
        db.hideBlizzardPreyWidget = not db.hideBlizzardPreyWidget
        print("|cffd6a800EasyPreyProgress|r Blizzard prey widget verbergen: " .. (db.hideBlizzardPreyWidget and "aan" or "uit"))
    elseif msg == "debug" then
        debugEnabled = not debugEnabled
        print("|cffd6a800EasyPreyProgress|r debug " .. (debugEnabled and "aan" or "uit"))
    elseif msg == "tooltip" then
        local tooltip = preyWidgetCache and preyWidgetCache.tooltip or nil
        if tooltip and tooltip ~= "" then
            print("|cffd6a800EasyPreyProgress tooltip:|r " .. tooltip:gsub("[\r\n]+", " | "))
        else
            print("|cffd6a800EasyPreyProgress|r geen cached prey-tooltip gevonden")
        end
    elseif msg == "traptext" then
        local trapText = extractTrapTextFromWidgetFrame() or extractTrapTextFromObjectives(getActivePreyQuestID())
        if trapText then
            print("|cffd6a800EasyPreyProgress trap text:|r " .. trapText)
        else
            print("|cffd6a800EasyPreyProgress|r geen trap-tekst gevonden op widget of objectives")
        end
    elseif msg == "inspecthide" then
        printTrackedPreyFrameTree()
    elseif msg == "inspectvisible" then
        printVisibleUiFrames()
    elseif msg == "inspecticons" then
        printVisibleUiIcons()
    elseif msg == "inspectcursor" then
        printVisibleFramesNearCursor()
    elseif msg == "inspecttimer" then
        printTimerTrackerTree()
    else
        print("|cffd6a800EasyPreyProgress|r commands: /epp lock, /epp unlock, /epp show, /epp hide, /epp reset, /epp zone, /epp blizz, /epp debug, /epp tooltip, /epp traptext, /epp inspecthide, /epp inspectvisible, /epp inspecticons, /epp inspectcursor, /epp inspecttimer")
    end

    if addon.frame then
        applyLayout()
        addon:Refresh()
    end
end

addon:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        getDB()
        createUI()
        applyLayout()
        installPreyWidgetHook()
        self:SetScript("OnUpdate", function(_, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 0.5 then
                self.elapsed = 0
                self:Refresh()
            end
        end)
        self:Refresh()
        return
    end

    if event == "ADDON_LOADED" and arg1 == "Blizzard_UIWidgets" then
        installPreyWidgetHook()
    end

    if not self.frame then
        return
    end

    applyLayout()
    self:Refresh()
end)
