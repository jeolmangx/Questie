dofile("setupTests.lua")

describe("TrackerZoneFilter", function()
    local TrackerZoneFilter, QuestiePlayer, ZoneDB, QuestieDB
    local playerArea
    local quests

    local function _Quest(objectives, fields)
        local quest = fields or {}
        quest.Objectives = objectives
        quest.IsComplete = function(self) return self.isComplete and 1 or 0 end
        return quest
    end

    local function _Objective(spawns, completed)
        return {Completed = completed, spawnList = {{Spawns = spawns}}}
    end

    before_each(function()
        playerArea = 12 -- Elwynn Forest
        QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
        QuestiePlayer.GetCurrentZoneId = function(_, requireZone)
            assert.is_true(requireZone)
            return playerArea
        end
        ZoneDB = QuestieLoader:ImportModule("ZoneDB")
        ZoneDB.GetParentZoneId = function(_, id) return ({[9] = 12, [10057] = 206, [206] = 495})[id] end
        ZoneDB.IsDungeonZone = function(id) return id == 10057 or id == 206 end
        ZoneDB.GetAreaIdByName = function(_, name) return ({["Elwynn Forest"] = 12, ["Westfall"] = 40})[name] end
        QuestieDB = QuestieLoader:ImportModule("QuestieDB")
        QuestieDB.GetNPC = function(_, id)
            if id == 10 then
                return {spawns = {[1519] = {{12, 15}}}}
            end
        end
        QuestieDB.GetObject = function(_, id)
            if id == 20 then
                return {spawns = {[40] = {{25, 30}}}}
            end
        end
        QuestieLoader:ImportModule("Phasing").IsSpawnVisible = function(phase) return phase ~= 2 end
        dofile("Modules/Tracker/TrackerZoneFilter.lua")
        TrackerZoneFilter = QuestieLoader:ImportModule("TrackerZoneFilter")
        quests = {}
    end)

    it("compares all unfinished spawn areas and ignores the assigned zone when a location is known", function()
        quests[1] = _Quest({_Objective({[9] = {{20, 20}}, [40] = {{30, 40}}})}, {zoneOrSort = 1519})
        quests[2] = _Quest({_Objective({[12] = {{18, 40}}}, true), _Objective({[40] = {{30, 40}}})}, {zoneOrSort = 12})
        quests[3] = _Quest({_Objective({[12] = {{10, 15, 2}}, [40] = {{30, 40}}})})
        assert.same({[2] = true, [3] = true}, TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = 40
        assert.is_nil(TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = 1519
        assert.same({[1] = true, [2] = true, [3] = true}, TrackerZoneFilter.GetHiddenQuests(quests))
    end)

    it("includes waypoint locations and sparse special objectives", function()
        quests[1] = _Quest({}, {SpecialObjectives = {[123] = {spawnList = {{Waypoints = {[40] = {{{10, 15}}}}}}}}})
        assert.same({[1] = true}, TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = 40
        assert.is_nil(TrackerZoneFilter.GetHiddenQuests(quests))
    end)

    it("switches to the NPC or object turn-in once the quest is complete", function()
        quests[1] = _Quest({_Objective({[12] = {{18, 40}}}, true)}, {
            isComplete = true, Finisher = {NPC = {10}, GameObject = {20}}, zoneName = "Elwynn Forest",
        })
        assert.same({[1] = true}, TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = 1519
        assert.is_nil(TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = 40
        assert.is_nil(TrackerZoneFilter.GetHiddenQuests(quests))
    end)

    it("prefers the native header to the database fallback and keeps unresolved quests visible", function()
        quests[1] = _Quest({}, {zoneName = "Westfall", zoneOrSort = 12})
        quests[2] = _Quest({}, {zoneName = "Class", zoneOrSort = -61})
        quests[3] = _Quest({}, {zoneOrSort = 40})
        quests[4] = _Quest({_Objective({[40] = {{20, 20}}}), {}}, {zoneOrSort = 40})

        assert.same({[1] = true, [3] = true}, TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = nil
        assert.is_nil(TrackerZoneFilter.GetHiddenQuests(quests))
    end)

    it("matches a dungeon floor to the dungeon without matching the outdoor entrance zone", function()
        quests[1] = _Quest({_Objective({[206] = {{-1, -1}}})})
        quests[2] = _Quest({_Objective({[495] = {{58, 58}}})})
        playerArea = 495
        assert.same({[1] = true}, TrackerZoneFilter.GetHiddenQuests(quests))

        playerArea = 10057
        assert.same({[2] = true}, TrackerZoneFilter.GetHiddenQuests(quests))
    end)
end)
