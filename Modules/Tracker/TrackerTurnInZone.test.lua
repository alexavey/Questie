dofile("setupTests.lua")

describe("TrackerTurnInZone", function()
    local resolver, quest, npcs, objects, names, maps, parents, dungeonNames, visible
    local originalMap, originalProfile, originalIsInInstance
    local QuestieDB, ZoneDB, Phasing

    before_each(function()
        originalMap, originalProfile = _G.C_Map, Questie.db.profile
        originalIsInInstance = _G.IsInInstance
        Questie.db.profile = {trackerMoveCompletedQuestsToTurnInZone = true, trackerSortObjectives = "byZone"}
        names = {[12] = "Elwynn Forest", [13] = "Northshire Abbey", [40] = "Westfall", [41] = "Moonbrook", [14] = "Durotar"}
        maps = {[12] = 1429, [13] = 1429, [40] = 1436, [41] = 1436, [14] = 1411}
        parents = {[13] = 12, [41] = 40, [4000] = 1581}
        dungeonNames = {[1581] = "The Deadmines", [4000] = "The Deadmines"}
        _G.C_Map = {
            GetAreaInfo = function(id) return names[id] end,
            GetMapInfo = function(id) return id and {mapType = 3} end,
        }
        ZoneDB = QuestieLoader:ImportModule("ZoneDB")
        ZoneDB.GetParentZoneId = function(_, id) return parents[id] end
        ZoneDB.GetUiMapIdByAreaId = function(_, id) return maps[id] end
        ZoneDB.GetAreaIdByName = function(_, name)
            for id, zoneName in pairs(names) do
                if zoneName == name then return id end
            end
        end
        ZoneDB.GetLocalizedDungeonName = function(_, id) return dungeonNames[id] end
        ZoneDB.IsDungeonZone = function(id) return dungeonNames[id] ~= nil end
        npcs = {[1] = {friendly = true, spawns = {[40] = {{50, 50}}}}}
        objects = {[2] = {spawns = {[40] = {{10, 20}}}}}
        QuestieDB = QuestieLoader:ImportModule("QuestieDB")
        QuestieDB.GetNPC = spy.new(function(_, id) return npcs[id] end)
        QuestieDB.GetObject = spy.new(function(_, id) return objects[id] end)
        visible = {[1] = true, [2] = false}
        Phasing = QuestieLoader:ImportModule("Phasing")
        Phasing.IsSpawnVisible = spy.new(function(phase)
            if not phase then return true end
            return visible[phase]
        end)
        quest = {
            Id = 123, zoneOrSort = 12, zoneName = "Northshire Abbey", completionState = 1, Objectives = {}, level = 10,
            Finisher = {NPC = {1}}, IsComplete = function(self) return self.completionState end,
        }
        dofile("Modules/Tracker/TrackerTurnInZone.lua")
        resolver = QuestieLoader:ImportModule("TrackerTurnInZone")
    end)

    after_each(function()
        _G.C_Map, Questie.db.profile = originalMap, originalProfile
        _G.IsInInstance = originalIsInInstance
    end)

    it("does nothing by default and does not read finisher metadata", function()
        Questie.db.profile.trackerMoveCompletedQuestsToTurnInZone = false

        assert.is_nil(resolver.GetGroupName(quest))
        assert.spy(QuestieDB.GetNPC).was.not_called()
        assert.spy(Phasing.IsSpawnVisible).was.not_called()
    end)

    for _, mode in ipairs({"byZone", "byZonePlayerProximity", "byZonePlayerProximityReversed"}) do
        it("moves a completed quest in " .. mode, function()
            Questie.db.profile.trackerSortObjectives = mode

            assert.are.equal("Westfall", resolver.GetGroupName(quest))
        end)
    end

    for _, mode in ipairs({"byLevel", "byLevelReversed", "byProximity", "byProximityReversed", "byComplete", "byCompleteReversed"}) do
        it("does not change grouping or read finishers in " .. mode, function()
            Questie.db.profile.trackerSortObjectives = mode

            assert.is_nil(resolver.GetGroupName(quest))
            assert.spy(QuestieDB.GetNPC).was.not_called()
        end)
    end

    it("does not move incomplete quests", function()
        quest.completionState = 0

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("uses Questie's additional completion without overriding failure", function()
        quest.completionState, quest.isComplete = 0, true
        assert.are.equal("Westfall", resolver.GetGroupName(quest))

        quest.completionState = -1
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("reevaluates completion reversal and setting toggles", function()
        assert.are.equal("Westfall", resolver.GetGroupName(quest))
        quest.completionState, quest.isComplete = 0, false
        assert.is_nil(resolver.GetGroupName(quest))
        quest.completionState = 1
        assert.are.equal("Westfall", resolver.GetGroupName(quest))
        Questie.db.profile.trackerMoveCompletedQuestsToTurnInZone = false
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("does not mutate native or database metadata", function()
        quest.enrichment = {zoneOrSort = 12, Finisher = quest.Finisher}
        local original = {zoneOrSort = 12, Finisher = {NPC = {1}}}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
        assert.are.equal("Northshire Abbey", quest.zoneName)
        assert.are.equal(12, quest.zoneOrSort)
        assert.are.same(original, quest.enrichment)
        assert.are.equal(quest.Finisher, quest.enrichment.Finisher)
    end)

    it("preserves a same-zone native subzone header", function()
        npcs[1].spawns = {[12] = {{50, 50}}, [13] = {{20, 20}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("accepts several finishers and spawn subzones in one normalized zone", function()
        quest.Finisher = {NPC = {1, 3}, GameObject = {2}}
        npcs[3] = {friendly = true, spawns = {[41] = {{20, 20}, {30, 30}}}}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
    end)

    it("supports an object-only turn-in", function()
        quest.Finisher = {GameObject = {2}}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
    end)

    it("preserves quests with distinct eligible NPC zones", function()
        npcs[1].spawns[14] = {{20, 20}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests with different NPC and object destinations", function()
        quest.Finisher.GameObject = {2}
        objects[2].spawns = {[14] = {{20, 20}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("excludes opposite-faction NPCs even when their location is missing", function()
        quest.Finisher.NPC = {1, 3}
        npcs[3] = {friendly = false}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
        npcs[1].friendly = false
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests with unknown NPC eligibility", function()
        quest.Finisher.NPC = {1, 3}
        npcs[3] = {spawns = {[14] = {{20, 20}}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("excludes invisible spawn phases and reevaluates phase changes", function()
        npcs[1].spawns = {[40] = {{50, 50, 1}}, [14] = {{20, 20, 2}}}
        assert.are.equal("Westfall", resolver.GetGroupName(quest))

        visible[2] = true
        assert.is_nil(resolver.GetGroupName(quest))
        visible[1] = false
        assert.are.equal("Durotar", resolver.GetGroupName(quest))
    end)

    it("preserves quests when all finishers are phased out", function()
        npcs[1].spawns = {[40] = {{50, 50, 2}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when phase eligibility is unknown", function()
        npcs[1].spawns[14] = {{50, 50, 3}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("applies phase visibility to object finishers too", function()
        quest.Finisher = {GameObject = {2}}
        objects[2].spawns[14] = {{20, 20, 2}}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
    end)

    it("preserves remote or automatic completions without a travel destination", function()
        quest.Finisher = {}
        assert.is_nil(resolver.GetGroupName(quest))
        quest.Finisher = nil
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when an additional NPC is unknown", function()
        quest.Finisher.NPC = {1, 3}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when an additional object is unknown", function()
        quest.Finisher.GameObject = {3}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when an eligible finisher has no locations", function()
        npcs[1].spawns = nil
        assert.is_nil(resolver.GetGroupName(quest))
        npcs[1].spawns = {}
        assert.is_nil(resolver.GetGroupName(quest))
        npcs[1].spawns = {[40] = {}}
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("reevaluates metadata arriving after the first grouping request", function()
        npcs[1] = nil
        assert.is_nil(resolver.GetGroupName(quest))
        npcs[1] = {friendly = true, spawns = {[40] = {{50, 50}}}}
        assert.are.equal("Westfall", resolver.GetGroupName(quest))
        npcs[1] = {friendly = true, spawns = {[14] = {{50, 50}}}}
        assert.are.equal("Durotar", resolver.GetGroupName(quest))
    end)

    it("uses actual dungeon zones for sentinel spawns, not their entrances", function()
        npcs[1].spawns = {[1581] = {{-1, -1}}, [4000] = {{-1, -1}}}
        parents[1581] = 40

        assert.are.equal("The Deadmines", resolver.GetGroupName(quest))
    end)

    it("preserves the native header for turn-ins in the same canonical dungeon", function()
        quest.zoneOrSort, quest.zoneName = 4000, "The Deadmines"
        npcs[1].spawns = {[1581] = {{-1, -1}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests with an unrecognized dungeon sentinel", function()
        npcs[1].spawns = {[40] = {{-1, -1}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("supports waypoint-only outdoor NPC finishers", function()
        npcs[1].spawns = nil
        npcs[1].waypoints = {[40] = {{{10, 20}, {20, 30}}}}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
    end)

    it("does not choose a single zone from multi-zone patrols", function()
        npcs[1].waypoints = {[14] = {{{10, 20}, {20, 30}}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("does not reintroduce invisible spawns through same-zone patrol data", function()
        npcs[1].spawns[14] = {{20, 20, 2}}
        npcs[1].waypoints = {[14] = {{{10, 20}, {20, 30}}}}

        assert.are.equal("Westfall", resolver.GetGroupName(quest))
    end)

    it("preserves quests with missing patrol points", function()
        npcs[1].spawns = nil
        npcs[1].waypoints = {[40] = {{}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves waypoint-only dungeon finishers, which QuestFinisher cannot locate", function()
        npcs[1].spawns = nil
        npcs[1].waypoints = {[1581] = {{{10, 20}}}}

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves profession and class categories even with a geographic-looking header", function()
        quest.zoneOrSort = -81

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves non-geographic native headers even with a positive database zone", function()
        quest.zoneName = "Shaman"

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("uses the database zone only when there is no native header", function()
        quest.zoneName = nil
        assert.are.equal("Westfall", resolver.GetGroupName(quest))
        quest.zoneOrSort = nil
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when a source map is unavailable", function()
        maps[12] = nil

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when any destination map is unavailable", function()
        maps[40] = nil

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when a destination's parent zone is unknown", function()
        parents[40] = 99

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when destination names or map info are missing", function()
        names[40] = nil
        assert.is_nil(resolver.GetGroupName(quest))
        names[40] = "Westfall"
        C_Map.GetMapInfo = function() return nil end
        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("does not use continents as geographic quest groups", function()
        C_Map.GetMapInfo = function() return {mapType = 2} end

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    it("preserves quests when the map type is unknown", function()
        C_Map.GetMapInfo = function() return {} end

        assert.is_nil(resolver.GetGroupName(quest))
    end)

    for _, coords in ipairs({{50}, {101, 50}, {50, -2}}) do
        it("preserves quests with unusable finisher coordinates", function()
            npcs[1].spawns = {[40] = {coords}}

            assert.is_nil(resolver.GetGroupName(quest))
        end)
    end

    describe("shared tracker grouping", function()
        local utils, tracked

        before_each(function()
            dofile("Modules/Tracker/TrackerUtils.lua")
            dofile("Modules/Tracker/Sorter/Sorter.lua")
            dofile("Modules/Tracker/Sorter/byZone.lua")
            dofile("Modules/Tracker/Sorter/byLevel.lua")
            utils = QuestieLoader:ImportModule("TrackerUtils")
            tracked = {
                [123] = quest,
                [124] = {Id = 124, zoneOrSort = 40, zoneName = "Westfall", Objectives = {}, level = 10,
                    IsComplete = function() return 0 end},
            }
            QuestieLoader:ImportModule("TrackerData").GetQuests = function() return tracked end
            QuestieLoader:ImportModule("QuestieLib").GetQuestTypeSuffix = function() return "" end
            QuestieLoader:ImportModule("QuestieLib").GetQuestTypeSuffixPriority = function() return 0 end
            _G.IsInInstance = function() return true end
            C_Map.GetBestMapForUnit = function() return 1429 end
            C_Map.GetMapInfo = function(id)
                return id == 947 and {mapType = 2, name = "Azeroth", parentMapID = 947}
                    or {mapType = 3, parentMapID = 947}
            end
            QuestieLoader:ImportModule("DistanceUtils").GetNearestSpawnForQuest = function() return {50, 50}, 40, "", 100 end
        end)

        for _, mode in ipairs({"byZone", "byZonePlayerProximity", "byZonePlayerProximityReversed"}) do
            it("merges the completed quest into the destination group in " .. mode, function()
                Questie.db.profile.trackerSortObjectives = mode

                local ids, details = utils:GetSortedQuestIds()

                assert.are.equal(2, #ids)
                assert.are.equal("Westfall", details[123].zoneName)
                assert.are.equal("Westfall", details[124].zoneName)
                assert.are.equal(quest, details[123].quest)
                assert.are.equal("Northshire Abbey", quest.zoneName)
                assert.are.equal("Westfall", utils.GetQuestGroupName(quest))
                quest.completionState = 0
                local _, reverted = utils:GetSortedQuestIds()
                assert.are.equal("Northshire Abbey", reverted[123].zoneName)
            end)
        end

        it("keeps non-zone sorting's synthetic group when enabled", function()
            Questie.db.profile.trackerSortObjectives = "byLevel"

            local _, details = utils:GetSortedQuestIds()

            assert.are.equal("Quests (By Level)", details[123].zoneName)
            assert.are.equal("Quests (By Level)", utils.GetQuestGroupName(quest))
        end)

        it("keeps the native header for same-zone turn-ins", function()
            npcs[1].spawns = {[12] = {{50, 50}}}

            assert.are.equal("Northshire Abbey", utils.GetQuestGroupName(quest))
        end)
    end)
end)
