---@class TrackerTurnInZone
local TrackerTurnInZone = QuestieLoader:CreateModule("TrackerTurnInZone")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type Phasing
local Phasing = QuestieLoader:ImportModule("Phasing")

local zoneSortModes = {byZone = true, byZonePlayerProximity = true, byZonePlayerProximityReversed = true}

---@param areaId AreaId?
---@return AreaId?, string?
local function _GetZone(areaId)
    if type(areaId) ~= "number" or areaId <= 0 then
        return nil
    end

    local parent = ZoneDB:GetParentZoneId(areaId)
    -- Dungeon aliases normalize to the dungeon itself, never to its outdoor entrance.
    if parent and ((not ZoneDB.IsDungeonZone(areaId)) or ZoneDB.IsDungeonZone(parent)) then
        areaId = parent
    end
    if ZoneDB.IsDungeonZone(areaId) then
        local name = ZoneDB:GetLocalizedDungeonName(areaId)
        if name and name ~= "" then
            return areaId, name
        end
        return nil
    end

    local uiMapId = ZoneDB:GetUiMapIdByAreaId(areaId)
    local mapInfo = uiMapId and C_Map.GetMapInfo(uiMapId)
    local mapType = mapInfo and mapInfo.mapType
    local name = C_Map.GetAreaInfo(areaId)
    if (mapType == 3 or mapType == 4 or mapType == 5) and name and name ~= "" then
        return areaId, name
    end
    return nil
end

---@param zones table<AreaId, string>
---@param areaId AreaId
---@param coords CoordPair
---@param waypoint boolean? Patrol points have no spawn phase.
---@return boolean reliable
local function _AddSpawnZone(zones, areaId, coords, waypoint)
    local x, y = coords[1], coords[2]
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local visible = waypoint or Phasing.IsSpawnVisible(coords[3])
    if visible == false then
        return true
    elseif visible ~= true then
        return false
    end

    if x == -1 or y == -1 then
        if not ZoneDB.IsDungeonZone(areaId) then
            return false
        end
    elseif not (x >= 0 and x <= 100 and y >= 0 and y <= 100) then
        return false
    end
    local zoneId, name = _GetZone(areaId)
    if not zoneId then
        return false
    end
    zones[zoneId] = name
    return true
end

---@param finisher NPC|Object?
---@param zones table<AreaId, string>
---@return boolean reliable
local function _CollectZones(finisher, zones)
    if not finisher then
        return false
    end
    local hasLocations = false
    for areaId, spawns in pairs(finisher.spawns or {}) do
        if not next(spawns) then
            return false
        end
        for _, coords in pairs(spawns) do
            hasLocations = true
            if not _AddSpawnZone(zones, areaId, coords) then
                return false
            end
        end
    end

    -- QuestFinisher uses the first patrol point when a zone has no spawn. Do not reintroduce phased-out spawns.
    for areaId, patrols in pairs(finisher.waypoints or {}) do
        if not (finisher.spawns and finisher.spawns[areaId]) then
            if ZoneDB.IsDungeonZone(areaId) or not next(patrols) then
                return false
            end
            for _, patrol in pairs(patrols) do
                if not patrol[1] or not _AddSpawnZone(zones, areaId, patrol[1], true) then
                    return false
                end
                hasLocations = true
            end
        end
    end
    return hasLocations
end

---Optional display-only override. Reevaluate current metadata and phases; never cache a destination or use player distance.
---@param quest TrackerQuest
---@return string? groupName Nil preserves the original tracker group.
function TrackerTurnInZone.GetGroupName(quest)
    local profile = Questie.db.profile
    if not profile.trackerMoveCompletedQuestsToTurnInZone or not zoneSortModes[profile.trackerSortObjectives] then
        return nil
    end
    local complete = quest:IsComplete()
    if complete == -1 or (complete ~= 1 and quest.isComplete ~= true) then
        return nil
    end
    if quest.zoneOrSort and quest.zoneOrSort <= 0 then
        return nil
    end

    local sourceArea = quest.zoneOrSort
    if quest.zoneName then
        sourceArea = ZoneDB:GetAreaIdByName(quest.zoneName)
        if not sourceArea and quest.zoneOrSort and ZoneDB:GetLocalizedDungeonName(quest.zoneOrSort) == quest.zoneName then
            sourceArea = quest.zoneOrSort
        end
    end
    local sourceZone = _GetZone(sourceArea)
    if not sourceZone or not quest.Finisher then
        return nil
    end

    local zones = {}
    for _, npcId in pairs(quest.Finisher.NPC or {}) do
        local npc = QuestieDB:GetNPC(npcId)
        if not npc or npc.friendly == nil then
            return nil
        end
        if npc.friendly and not _CollectZones(npc, zones) then
            return nil
        end
    end
    for _, objectId in pairs(quest.Finisher.GameObject or {}) do
        if not _CollectZones(QuestieDB:GetObject(objectId), zones) then
            return nil
        end
    end

    local zoneId, name = next(zones)
    if zoneId and zoneId ~= sourceZone and not next(zones, zoneId) then
        return name
    end
    return nil
end
