---@class TrackerZoneFilter
local TrackerZoneFilter = QuestieLoader:CreateModule("TrackerZoneFilter")

---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type Phasing
local Phasing = QuestieLoader:ImportModule("Phasing")

local function _GetZone(areaId)
    if type(areaId) ~= "number" or areaId <= 0 then
        return nil
    end

    local parent = ZoneDB:GetParentZoneId(areaId)
    if not parent then
        return areaId
    end

    local visited = {}
    while parent and (not ZoneDB.IsDungeonZone(areaId) or ZoneDB.IsDungeonZone(parent)) do
        if visited[parent] then
            return nil
        end
        visited[areaId] = true
        areaId = parent
        parent = ZoneDB:GetParentZoneId(areaId)
    end
    return areaId
end

local function _HasVisibleSpawn(entries)
    for _, coords in pairs(entries) do
        if coords[1] and coords[2] and Phasing.IsSpawnVisible(coords[3]) then
            return true
        end
    end
    return false
end

local function _AddLocations(zones, locations, areWaypoints)
    local hasLocation = false
    for areaId, entries in pairs(locations or {}) do
        if (areWaypoints and next(entries)) or (not areWaypoints and _HasVisibleSpawn(entries)) then
            -- Dungeon spawn placeholders are keyed by the dungeon area, even when the map pin uses its entrance.
            local zone = _GetZone(areaId)
            if zone then
                zones[zone] = true
                hasLocation = true
            end
        end
    end
    return hasLocation
end

local function _AddObjectiveLocations(zones, objectives)
    local hasUnknown = false
    for _, objective in pairs(objectives) do
        if not objective.Completed then
            local hasLocation = false
            for _, spawn in pairs(objective.spawnList or {}) do
                local hasSpawns = _AddLocations(zones, spawn.Spawns)
                local hasWaypoints = _AddLocations(zones, spawn.Waypoints, true)
                hasLocation = hasLocation or hasSpawns or hasWaypoints
            end
            hasUnknown = hasUnknown or not hasLocation
        end
    end
    return hasUnknown
end

local function _AddFinishers(zones, ids, getEntity)
    local hasUnknown = false
    for _, id in ipairs(ids or {}) do
        local entity = getEntity(QuestieDB, id)
        local hasSpawns = entity and _AddLocations(zones, entity.spawns)
        local hasWaypoints = entity and _AddLocations(zones, entity.waypoints, true)
        hasUnknown = hasUnknown or not (hasSpawns or hasWaypoints)
    end
    return hasUnknown
end

local function _IsOutsideZone(quest, currentZone)
    local zones = {}
    local hasUnknown
    local complete = quest:IsComplete()
    if complete == 1 or (complete ~= -1 and quest.isComplete) then
        local finisher = quest.Finisher or {}
        local hasUnknownNpc = _AddFinishers(zones, finisher.NPC, QuestieDB.GetNPC)
        local hasUnknownObject = _AddFinishers(zones, finisher.GameObject, QuestieDB.GetObject)
        hasUnknown = hasUnknownNpc or hasUnknownObject
    else
        local hasUnknownObjective = _AddObjectiveLocations(zones, quest.Objectives)
        local hasUnknownSpecial = _AddObjectiveLocations(zones, quest.SpecialObjectives or {})
        hasUnknown = hasUnknownObjective or hasUnknownSpecial
    end

    if next(zones) then
        return not zones[currentZone] and not hasUnknown
    end

    local headerAreaId = quest.zoneName and ZoneDB:GetAreaIdByName(quest.zoneName)
    local fallbackZone = _GetZone(headerAreaId) or _GetZone(quest.zoneOrSort)
    return fallbackZone ~= nil and fallbackZone ~= currentZone
end

---@param quests table<QuestId, TrackerQuest>
---@return table<QuestId, boolean>? hiddenQuests
function TrackerZoneFilter.GetHiddenQuests(quests)
    local currentZone = _GetZone(QuestiePlayer:GetCurrentZoneId(true))
    if not currentZone then
        return nil
    end

    local hiddenQuests
    for questId, quest in pairs(quests) do
        if _IsOutsideZone(quest, currentZone) then
            hiddenQuests = hiddenQuests or {}
            hiddenQuests[questId] = true
        end
    end
    return hiddenQuests
end
