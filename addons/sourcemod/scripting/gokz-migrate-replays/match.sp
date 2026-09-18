#define MIGRATE_MATCH_PER_TICK 500
#define MIGRATE_CREATED_TOLERANCE 300



// =====[ STEP ]=====

bool Step_MatchReplays()
{
	int end = IntMin(g_Cursor + MIGRATE_MATCH_PER_TICK, g_Replays.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateReplay replay;
		g_Replays.GetArray(i, replay);
		MatchReplay(i, replay);
		g_Replays.SetArray(i, replay);
	}
	g_Cursor = end;
	Migrate_Log("Matched %d of %d replays.", g_Cursor, g_Replays.Length);
	return g_Cursor >= g_Replays.Length;
}



// =====[ PUBLIC ]=====

void GetMatchStatusName(MatchStatus status, char[] buffer, int maxlength)
{
	static const char names[][] =
	{
		"unmatched", "matched", "duplicate", "record_missing", "map_unknown", "course_unknown", "player_unknown", "cheater", "unreadable", "unsupported_type"
	};
	strcopy(buffer, maxlength, names[view_as<int>(status)]);
}



// =====[ PRIVATE ]=====

static void MatchReplay(int index, MigrateReplay replay)
{
	if (replay.status != MatchStatus_Unmatched && replay.status != MatchStatus_Cheater)
	{
		return;
	}
	if (replay.status == MatchStatus_Cheater)
	{
		strcopy(replay.targetMap, sizeof(MigrateReplay::targetMap), replay.map);
		Migrate_Log("Cheater replay %s (steamid %d, map %s) has no database record and will %s.", replay.path, replay.steamID, replay.map, gCV_gokz_migrate_replays_include_cheaters.BoolValue ? "be imported as a cheater replay" : "be skipped");
		return;
	}

	if (!IsKnownPlayer(replay.steamID))
	{
		replay.status = MatchStatus_PlayerUnknown;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "steamid %d is not in Players", replay.steamID);
		Migrate_Log("Replay %s belongs to steamid %d which is not in the legacy Players table.", replay.path, replay.steamID);
		return;
	}

	if (replay.replayType == ReplayType_Jump)
	{
		MatchJumpReplay(index, replay);
		return;
	}
	MatchRunReplay(index, replay);
}

static void MatchRunReplay(int index, MigrateReplay replay)
{
	int mapIndex = FindMapIndexByName(replay.map);
	if (mapIndex == -1)
	{
		replay.status = MatchStatus_MapUnknown;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "map %s is not in Maps", replay.map);
		Migrate_Log("Run replay %s is for map %s which is not in the legacy Maps table.", replay.path, replay.map);
		return;
	}
	LegacyMap map;
	g_Maps.GetArray(mapIndex, map);

	int courseIndex = FindCourseIndex(map.mapID, replay.course);
	if (courseIndex == -1)
	{
		replay.status = MatchStatus_CourseUnknown;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "course %d of %s is not in MapCourses", replay.course, replay.map);
		Migrate_Log("Run replay %s is for course %d of %s which is not in the legacy MapCourses table.", replay.path, replay.course, replay.map);
		return;
	}
	LegacyCourse course;
	g_Courses.GetArray(courseIndex, course);

	int runTime = GOKZ_DB_TimeFloatToInt(replay.time);
	int timeIndex = FindClosestTime(replay, course.mapCourseID, runTime);
	if (timeIndex == -1)
	{
		replay.status = MatchStatus_Unmatched;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "no Times row for steamid %d on %s course %d mode %d style %d with RunTime %d", replay.steamID, replay.map, replay.course, replay.mode, replay.style, runTime);
		Migrate_Log("Run replay %s has no matching Times row (steamid %d, %s course %d, mode %d, style %d, %d ms, recorded %d).", replay.path, replay.steamID, replay.map, replay.course, replay.mode, replay.style, runTime, replay.timestamp);
		return;
	}

	LegacyTime time;
	g_Times.GetArray(timeIndex, time);
	char targetMap[64];
	if (!FindMigratedTimeMap(time.timeID, targetMap, sizeof(targetMap)))
	{
		replay.status = MatchStatus_RecordMissing;
		replay.recordID = time.timeID;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "matches TimeID %d which is not in the migrated database", time.timeID);
		Migrate_Log("Run replay %s matches TimeID %d but that time is not in the migrated database.", replay.path, time.timeID);
		return;
	}

	if (!ClaimTimeReplay(timeIndex, index, replay))
	{
		return;
	}
	replay.status = MatchStatus_Matched;
	replay.recordID = time.timeID;
	replay.recordIndex = timeIndex;
	strcopy(replay.targetMap, sizeof(MigrateReplay::targetMap), targetMap);
	NoteCreatedDifference(replay, time.created);
	Migrate_Log("Run replay %s matches TimeID %d (steamid %d, %s course %d, %d ms, %d teleports).", replay.path, time.timeID, time.steamID, replay.targetMap, replay.course, time.runTime, time.teleports);
}

static void MatchJumpReplay(int index, MigrateReplay replay)
{
	int distance = RoundToNearest(replay.distance * GOKZ_DB_JS_DISTANCE_PRECISION);
	int jumpIndex = FindClosestJump(replay, distance);
	if (jumpIndex == -1)
	{
		replay.status = MatchStatus_Unmatched;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "no Jumpstats row for steamid %d type %d mode %d distance %d block %d", replay.steamID, replay.jumpType, replay.mode, distance, replay.block);
		Migrate_Log("Jump replay %s has no matching Jumpstats row (steamid %d, type %d, mode %d, distance %d, block %d, recorded %d).", replay.path, replay.steamID, replay.jumpType, replay.mode, distance, replay.block, replay.timestamp);
		return;
	}

	LegacyJump jump;
	g_Jumps.GetArray(jumpIndex, jump);
	if (!IsMigratedJump(jump.jumpID))
	{
		replay.status = MatchStatus_RecordMissing;
		replay.recordID = jump.jumpID;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "matches JumpID %d which is not in the migrated database", jump.jumpID);
		Migrate_Log("Jump replay %s matches JumpID %d but that jump is not in the migrated database.", replay.path, jump.jumpID);
		return;
	}

	if (!ClaimJumpReplay(jumpIndex, index, replay))
	{
		return;
	}
	replay.status = MatchStatus_Matched;
	replay.recordID = jump.jumpID;
	replay.recordIndex = jumpIndex;
	strcopy(replay.targetMap, sizeof(MigrateReplay::targetMap), replay.map);
	NoteCreatedDifference(replay, jump.created);
	Migrate_Log("Jump replay %s matches JumpID %d (steamid %d, type %d, mode %d, distance %d, block %d).", replay.path, jump.jumpID, jump.steamID, jump.jumpType, jump.mode, jump.distance, jump.block);
}

static int FindClosestTime(MigrateReplay replay, int mapCourseID, int runTime)
{
	int best = -1;
	int bestDelta = 0;
	for (int offset = -1; offset <= 1; offset++)
	{
		char key[64];
		TimeKey(replay.steamID, mapCourseID, replay.mode, replay.style, runTime + offset, key, sizeof(key));
		ArrayList candidates = ListMapGet(g_TimeIndexesByKey, key);
		if (candidates == null)
		{
			continue;
		}
		for (int i = 0; i < candidates.Length; i++)
		{
			int candidate = candidates.Get(i);
			LegacyTime time;
			g_Times.GetArray(candidate, time);
			int delta = AbsoluteDifference(time.created, replay.timestamp);
			if (best == -1 || delta < bestDelta)
			{
				best = candidate;
				bestDelta = delta;
			}
		}
		if (best != -1)
		{
			return best;
		}
	}
	return best;
}

static int FindClosestJump(MigrateReplay replay, int distance)
{
	int best = -1;
	int bestDelta = 0;
	for (int offset = -1; offset <= 1; offset++)
	{
		char key[64];
		JumpKey(replay.steamID, replay.jumpType, replay.mode, distance + offset, replay.block, key, sizeof(key));
		ArrayList candidates = ListMapGet(g_JumpIndexesByKey, key);
		if (candidates == null)
		{
			continue;
		}
		for (int i = 0; i < candidates.Length; i++)
		{
			int candidate = candidates.Get(i);
			LegacyJump jump;
			g_Jumps.GetArray(candidate, jump);
			int delta = AbsoluteDifference(jump.created, replay.timestamp);
			if (best == -1 || delta < bestDelta)
			{
				best = candidate;
				bestDelta = delta;
			}
		}
		if (best != -1)
		{
			return best;
		}
	}
	return best;
}

static bool ClaimTimeReplay(int timeIndex, int replayIndex, MigrateReplay replay)
{
	LegacyTime time;
	g_Times.GetArray(timeIndex, time);
	if (time.replayIndex == -1)
	{
		time.replayIndex = replayIndex;
		g_Times.SetArray(timeIndex, time);
		return true;
	}

	MigrateReplay existing;
	g_Replays.GetArray(time.replayIndex, existing);
	if (!IsBetterReplay(replay, existing))
	{
		MarkDuplicate(replay, time.timeID, existing.path);
		return false;
	}
	MarkDuplicate(existing, time.timeID, replay.path);
	g_Replays.SetArray(time.replayIndex, existing);
	time.replayIndex = replayIndex;
	g_Times.SetArray(timeIndex, time);
	return true;
}

static bool ClaimJumpReplay(int jumpIndex, int replayIndex, MigrateReplay replay)
{
	LegacyJump jump;
	g_Jumps.GetArray(jumpIndex, jump);
	if (jump.replayIndex == -1)
	{
		jump.replayIndex = replayIndex;
		g_Jumps.SetArray(jumpIndex, jump);
		return true;
	}

	MigrateReplay existing;
	g_Replays.GetArray(jump.replayIndex, existing);
	if (!IsBetterReplay(replay, existing))
	{
		MarkDuplicate(replay, jump.jumpID, existing.path);
		return false;
	}
	MarkDuplicate(existing, jump.jumpID, replay.path);
	g_Replays.SetArray(jump.replayIndex, existing);
	jump.replayIndex = replayIndex;
	g_Jumps.SetArray(jumpIndex, jump);
	return true;
}

static bool IsBetterReplay(MigrateReplay candidate, MigrateReplay existing)
{
	int candidateRank = CategoryRank(candidate.category);
	int existingRank = CategoryRank(existing.category);
	if (candidateRank != existingRank)
	{
		return candidateRank < existingRank;
	}
	return candidate.timestamp > existing.timestamp;
}

static int CategoryRank(ReplayCategory category)
{
	switch (category)
	{
		case ReplayCategory_Runs: return 0;
		case ReplayCategory_Jumps: return 0;
		case ReplayCategory_TempRuns: return 1;
	}
	return 2;
}

static void MarkDuplicate(MigrateReplay replay, int recordID, const char[] winnerPath)
{
	replay.status = MatchStatus_Duplicate;
	replay.recordID = recordID;
	replay.recordIndex = -1;
	FormatEx(replay.note, sizeof(MigrateReplay::note), "record %d is served by %s", recordID, winnerPath);
	Migrate_Log("Replay %s duplicates record %d which is served by %s.", replay.path, recordID, winnerPath);
}

static void NoteCreatedDifference(MigrateReplay replay, int created)
{
	int delta = AbsoluteDifference(created, replay.timestamp);
	if (delta <= MIGRATE_CREATED_TOLERANCE)
	{
		return;
	}
	FormatEx(replay.note, sizeof(MigrateReplay::note), "record created %d seconds away from the replay timestamp", delta);
	Migrate_Log("WARNING: replay %s matches record %d but the row was created %d seconds away from the replay timestamp.", replay.path, replay.recordID, delta);
}

static int AbsoluteDifference(int a, int b)
{
	if (a > b)
	{
		return a - b;
	}
	return b - a;
}
