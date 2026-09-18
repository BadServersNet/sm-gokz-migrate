#define MIGRATE_REPORT_ROWS_PER_TICK 5000



// =====[ STEPS ]=====

bool Step_ReportTimes()
{
	File report = Report_Times();
	int end = IntMin(g_Cursor + MIGRATE_REPORT_ROWS_PER_TICK, g_Times.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		LegacyTime time;
		g_Times.GetArray(i, time);
		if (time.replayIndex != -1)
		{
			continue;
		}
		char map[64];
		int course;
		DescribeCourse(time.mapCourseID, map, sizeof(map), course);
		char created[32];
		FormatUnixTime(time.created, created, sizeof(created));
		char migratedMap[64];
		bool migrated = FindMigratedTimeMap(time.timeID, migratedMap, sizeof(migratedMap));
		ReportLine(report, "%d,%d,%s,%d,%d,%d,%d,%d,%s,%d", time.timeID, time.steamID, map, course, time.mode, time.style, time.runTime, time.teleports, created, migrated ? 1 : 0);
	}
	g_Cursor = end;
	return g_Cursor >= g_Times.Length;
}

bool Step_ReportJumps()
{
	File report = Report_Jumps();
	int end = IntMin(g_Cursor + MIGRATE_REPORT_ROWS_PER_TICK, g_Jumps.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		LegacyJump jump;
		g_Jumps.GetArray(i, jump);
		if (jump.replayIndex != -1)
		{
			continue;
		}
		char created[32];
		FormatUnixTime(jump.created, created, sizeof(created));
		bool migrated = IsMigratedJump(jump.jumpID);
		ReportLine(report, "%d,%d,%d,%d,%d,%d,%d,%s,%d", jump.jumpID, jump.steamID, jump.jumpType, jump.mode, jump.distance, jump.isBlockJump, jump.block, created, migrated ? 1 : 0);
	}
	g_Cursor = end;
	return g_Cursor >= g_Jumps.Length;
}

bool Step_ReportReplays()
{
	File report = Report_Replays();
	int end = IntMin(g_Cursor + MIGRATE_REPORT_ROWS_PER_TICK, g_Replays.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateReplay replay;
		g_Replays.GetArray(i, replay);
		WriteReplayLine(report, replay);
	}
	g_Cursor = end;
	return g_Cursor >= g_Replays.Length;
}

bool Step_Summary()
{
	CloseReports();
	SummarizeTimes();
	SummarizeJumps();
	SummarizeReplays();
	Migrate_Log("Mode: %s.", gB_DryRun ? "DRY RUN, nothing was imported; rerun with sm_gokz_migrate_replays_run to apply" : "REAL RUN, matched replays were imported and queued for upload");
	Migrate_Log("Reports were written next to the log with the prefix %s", gC_ReportPrefix);
	return true;
}



// =====[ PRIVATE ]=====

static void DescribeCourse(int mapCourseID, char[] map, int maxlength, int &course)
{
	strcopy(map, maxlength, "?");
	course = -1;
	int courseIndex = FindCourseIndexByID(mapCourseID);
	if (courseIndex == -1)
	{
		return;
	}
	LegacyCourse courseRow;
	g_Courses.GetArray(courseIndex, courseRow);
	course = courseRow.course;
	int mapIndex = FindMapIndexByID(courseRow.mapID);
	if (mapIndex == -1)
	{
		return;
	}
	LegacyMap mapRow;
	g_Maps.GetArray(mapIndex, mapRow);
	strcopy(map, maxlength, mapRow.name);
}

static void WriteReplayLine(File report, MigrateReplay replay)
{
	char path[520];
	char category[16];
	char type[16];
	char map[136];
	char status[24];
	char targetMap[136];
	char key[400];
	char note[400];
	CsvEscape(replay.path, path, sizeof(path));
	GetCategoryName(replay.category, category, sizeof(category));
	GetReplayTypeName(replay.replayType, type, sizeof(type));
	CsvEscape(replay.map, map, sizeof(map));
	GetMatchStatusName(replay.status, status, sizeof(status));
	CsvEscape(replay.targetMap, targetMap, sizeof(targetMap));
	CsvEscape(replay.key, key, sizeof(key));
	CsvEscape(replay.note, note, sizeof(note));
	ReportLine(report, "%s,%s,%d,%s,%s,%d,%d,%d,%d,%d,%.3f,%d,%d,%.4f,%d,%d,%d,%s,%d,%s,%s,%d,%s",
		path, category, replay.formatVersion, type, map, replay.steamID, replay.mode, replay.style, replay.timestamp,
		replay.course, replay.time, replay.teleports, replay.jumpType, replay.distance, replay.block, replay.tickCount, replay.fileSize,
		status, replay.recordID, targetMap, key, replay.imported ? 1 : 0, note);
}

static void SummarizeTimes()
{
	int migrated = 0;
	int withReplay = 0;
	int migratedWithoutReplay = 0;
	for (int i = 0; i < g_Times.Length; i++)
	{
		LegacyTime time;
		g_Times.GetArray(i, time);
		char map[64];
		bool inOutput = FindMigratedTimeMap(time.timeID, map, sizeof(map));
		if (inOutput)
		{
			migrated++;
		}
		if (time.replayIndex != -1)
		{
			withReplay++;
			continue;
		}
		if (inOutput)
		{
			migratedWithoutReplay++;
		}
	}
	Migrate_Log("SUMMARY times: %d in the legacy database, %d in the migrated database, %d have a replay, %d migrated times have no replay.", g_Times.Length, migrated, withReplay, migratedWithoutReplay);
}

static void SummarizeJumps()
{
	int migrated = 0;
	int withReplay = 0;
	for (int i = 0; i < g_Jumps.Length; i++)
	{
		LegacyJump jump;
		g_Jumps.GetArray(i, jump);
		if (IsMigratedJump(jump.jumpID))
		{
			migrated++;
		}
		if (jump.replayIndex != -1)
		{
			withReplay++;
		}
	}
	Migrate_Log("SUMMARY jumps: %d in the legacy database, %d in the migrated database, %d have a replay, %d have no replay.", g_Jumps.Length, migrated, withReplay, g_Jumps.Length - withReplay);
}

static void SummarizeReplays()
{
	int counts[10];
	int imported = 0;
	int bytes = 0;
	for (int i = 0; i < g_Replays.Length; i++)
	{
		MigrateReplay replay;
		g_Replays.GetArray(i, replay);
		counts[view_as<int>(replay.status)]++;
		if (replay.imported)
		{
			imported++;
			bytes += replay.fileSize;
		}
	}
	Migrate_Log("SUMMARY replays: %d files scanned; %d matched a record, %d unmatched (no record), %d duplicates of another file, %d matched a record missing from the migrated database, %d unknown map, %d unknown course, %d unknown player, %d cheater replays, %d unreadable, %d unsupported type.",
		g_Replays.Length, counts[1], counts[0], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8], counts[9]);
	Migrate_Log("SUMMARY imports: %d replays queued for upload (%d bytes).", imported, bytes);
}
