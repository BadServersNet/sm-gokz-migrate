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
	Migrate_Detail("Matched %d of %d replays.", g_Cursor, g_Replays.Length);
	return g_Cursor >= g_Replays.Length;
}



// =====[ PUBLIC ]=====

void GetMatchStatusName(MatchStatus status, char[] buffer, int maxlength)
{
	static const char names[][] =
	{
		"unmatched", "matched", "duplicate", "record_missing", "map_unknown", "course_unknown", "player_unknown", "unreadable", "unsupported_type"
	};
	strcopy(buffer, maxlength, names[view_as<int>(status)]);
}



// =====[ PRIVATE ]=====

static void MatchReplay(int index, MigrateReplay replay)
{
	if (replay.status != MatchStatus_Unmatched)
	{
		return;
	}

	int playerIndex = FindPlayerIndex(replay.steamID);
	if (playerIndex == -1)
	{
		replay.status = MatchStatus_PlayerUnknown;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "steamid %d is not in Players", replay.steamID);
		Migrate_Detail("Replay %s belongs to steamid %d which is not in the legacy Players table.", replay.path, replay.steamID);
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
		Migrate_Detail("Run replay %s is for map %s which is not in the legacy Maps table.", replay.path, replay.map);
		return;
	}
	MigrateMap map;
	g_Maps.GetArray(mapIndex, map);

	int courseIndex = FindCourseIndex(map.mapID, replay.course);
	if (courseIndex == -1)
	{
		replay.status = MatchStatus_CourseUnknown;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "course %d of %s is not in MapCourses", replay.course, replay.map);
		Migrate_Detail("Run replay %s is for course %d of %s which is not in the legacy MapCourses table.", replay.path, replay.course, replay.map);
		return;
	}
	MigrateCourse course;
	g_Courses.GetArray(courseIndex, course);

	int runTime = GOKZ_DB_TimeFloatToInt(replay.time);
	int timeIndex = FindClosestTime(replay, course.mapCourseID, runTime);
	if (timeIndex == -1)
	{
		replay.status = MatchStatus_Unmatched;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "no Times row for steamid %d on %s course %d mode %d style %d with RunTime %d", replay.steamID, replay.map, replay.course, replay.mode, replay.style, runTime);
		Migrate_Detail("Run replay %s has no matching Times row (steamid %d, %s course %d, mode %d, style %d, %d ms, recorded %d).", replay.path, replay.steamID, replay.map, replay.course, replay.mode, replay.style, runTime, replay.timestamp);
		return;
	}

	MigrateTime time;
	g_Times.GetArray(timeIndex, time);
	replay.legacyTimeID = time.timeID;
	if (!time.keep)
	{
		replay.status = MatchStatus_RecordMissing;
		FormatEx(replay.note, sizeof(MigrateReplay::note), "matches legacy TimeID %d which is not migrated", time.timeID);
		Migrate_Detail("Run replay %s matches legacy TimeID %d but that time is not migrated, so the replay is left behind.", replay.path, time.timeID);
		return;
	}

	if (!ClaimTimeReplay(timeIndex, index, replay))
	{
		return;
	}
	replay.status = MatchStatus_Matched;
	replay.recordID = time.newTimeID;
	replay.recordIndex = timeIndex;
	GetTargetMapName(time.targetMapCourseID, replay.targetMap, sizeof(MigrateReplay::targetMap));
	NoteCreatedDifference(replay, time.created);
	Migrate_Detail("Run replay %s matches legacy TimeID %d which becomes TimeID %d (steamid %d, %s course %d, %d ms, %d teleports).", replay.path, time.timeID, time.newTimeID, time.steamID, replay.targetMap, replay.course, time.runTime, time.teleports);
}

static void GetTargetMapName(int mapCourseID, char[] buffer, int maxlength)
{
	int courseIndex = FindCourseIndexByID(mapCourseID);
	MigrateCourse course;
	g_Courses.GetArray(courseIndex, course);
	int mapIndex = FindMapIndexByID(course.targetMapID);
	MigrateMap map;
	g_Maps.GetArray(mapIndex, map);
	strcopy(buffer, maxlength, map.targetName);
}

static int FindClosestTime(MigrateReplay replay, int mapCourseID, int runTime)
{
	for (int offset = -1; offset <= 1; offset++)
	{
		char key[64];
		TimeKey(replay.steamID, mapCourseID, replay.mode, replay.style, runTime + offset, key, sizeof(key));
		int head;
		if (g_TimeIndexesByKey.GetValue(key, head))
		{
			return FindClosestTimeInChain(head, replay.timestamp);
		}
	}
	return -1;
}

static int FindClosestTimeInChain(int head, int timestamp)
{
	int best = head;
	int bestDelta = -1;
	int index = head;
	while (index != -1)
	{
		MigrateTime time;
		g_Times.GetArray(index, time);
		int delta = AbsoluteDifference(time.created, timestamp);
		if (bestDelta == -1 || delta <= bestDelta)
		{
			best = index;
			bestDelta = delta;
		}
		index = time.nextIndex;
	}
	return best;
}

static bool ClaimTimeReplay(int timeIndex, int replayIndex, MigrateReplay replay)
{
	MigrateTime time;
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
		case ReplayCategory_TempRuns: return 1;
	}
	return 2;
}

static void MarkDuplicate(MigrateReplay replay, int legacyTimeID, const char[] winnerPath)
{
	replay.status = MatchStatus_Duplicate;
	replay.legacyTimeID = legacyTimeID;
	replay.recordID = 0;
	replay.recordIndex = -1;
	FormatEx(replay.note, sizeof(MigrateReplay::note), "legacy TimeID %d is served by %s", legacyTimeID, winnerPath);
	Migrate_Detail("Replay %s duplicates legacy TimeID %d which is served by %s.", replay.path, legacyTimeID, winnerPath);
}

static void NoteCreatedDifference(MigrateReplay replay, int created)
{
	int delta = AbsoluteDifference(created, replay.timestamp);
	if (delta <= MIGRATE_CREATED_TOLERANCE)
	{
		return;
	}
	FormatEx(replay.note, sizeof(MigrateReplay::note), "record created %d seconds away from the replay timestamp", delta);
	Migrate_Detail("WARNING: replay %s matches legacy TimeID %d but the row was created %d seconds away from the replay timestamp.", replay.path, replay.legacyTimeID, delta);
}

static int AbsoluteDifference(int a, int b)
{
	if (a > b)
	{
		return a - b;
	}
	return b - a;
}
