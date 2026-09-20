#define MIGRATE_REPORT_ROWS_PER_TICK 5000



// =====[ STEPS ]=====

bool Step_ReportMaps()
{
	File report = Report_Maps();
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		char status[16];
		GetMapStatusName(map.status, status, sizeof(status));
		char name[136];
		char targetName[136];
		char note[520];
		CsvEscape(map.name, name, sizeof(name));
		CsvEscape(map.targetName, targetName, sizeof(targetName));
		CsvEscape(map.note, note, sizeof(note));
		ReportLine(report, "%d,%s,%s,%d,%d,%s,%d,%d,%s", map.mapID, name, status, map.targetMapID, map.newMapID, targetName, map.timeCount, map.validated ? 1 : 0, note);
	}
	return true;
}

bool Step_ReportPlayers()
{
	File report = Report_Players();
	for (int i = 0; i < g_Players.Length; i++)
	{
		MigratePlayer player;
		g_Players.GetArray(i, player);
		if (player.keep)
		{
			continue;
		}
		char alias[272];
		char lastPlayed[32];
		char created[32];
		CsvEscape(player.alias, alias, sizeof(alias));
		FormatUnixTime(player.lastPlayed, lastPlayed, sizeof(lastPlayed));
		FormatUnixTime(player.created, created, sizeof(created));
		ReportLine(report, "%d,%s,%d,%s,%s", player.steamID, alias, player.cheater, lastPlayed, created);
	}
	return true;
}

bool Step_ReportTimes()
{
	File report = Report_Times();
	int end = IntMin(g_Cursor + MIGRATE_REPORT_ROWS_PER_TICK, g_Times.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateTime time;
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
		ReportLine(report, "%d,%d,%d,%s,%d,%d,%d,%d,%d,%s,%d", time.timeID, time.newTimeID, time.steamID, map, course, time.mode, time.style, time.runTime, time.teleports, created, time.keep ? 1 : 0);
	}
	g_Cursor = end;
	return g_Cursor >= g_Times.Length;
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
	SummarizeMaps();
	SummarizePlayers();
	SummarizeTimes();
	SummarizeReplays();
	Migrate_Log("Mode: %s.", gB_DryRun ? "DRY RUN, nothing was written; rerun with sm_gokz_migrate_run to apply" : "REAL RUN, the gokz database was rebuilt with new IDs and the matched replays were queued for upload; change the map so gokz-localdb picks up the new MapID");
	Migrate_Log("Reports were written next to the log with the prefix %s", gC_ReportPrefix);
	return true;
}



// =====[ PRIVATE ]=====

static void GetMapStatusName(MapStatus status, char[] buffer, int maxlength)
{
	static const char names[][] = { "global", "renamed", "merged", "deleted", "hanging" };
	strcopy(buffer, maxlength, names[view_as<int>(status)]);
}

static void DescribeCourse(int mapCourseID, char[] map, int maxlength, int &course)
{
	strcopy(map, maxlength, "?");
	course = -1;
	int courseIndex = FindCourseIndexByID(mapCourseID);
	if (courseIndex == -1)
	{
		return;
	}
	MigrateCourse courseRow;
	g_Courses.GetArray(courseIndex, courseRow);
	course = courseRow.course;
	int mapIndex = FindMapIndexByID(courseRow.mapID);
	if (mapIndex == -1)
	{
		return;
	}
	MigrateMap mapRow;
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
	ReportLine(report, "%s,%s,%d,%s,%s,%d,%d,%d,%d,%d,%.3f,%d,%d,%d,%s,%d,%d,%s,%s,%d,%s",
		path, category, replay.formatVersion, type, map, replay.steamID, replay.mode, replay.style, replay.timestamp,
		replay.course, replay.time, replay.teleports, replay.tickCount, replay.fileSize,
		status, replay.legacyTimeID, replay.recordID, targetMap, key, replay.imported ? 1 : 0, note);
}

static void SummarizeMaps()
{
	int counts[5];
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		counts[view_as<int>(map.status)]++;
	}
	Migrate_Log("SUMMARY maps: %d in input, %d global kept, %d renamed, %d merged, %d deleted (not global), %d hanging (no times).", g_Maps.Length, counts[0], counts[1], counts[2], counts[3], counts[4]);

	int keptCourses = 0;
	for (int i = 0; i < g_Courses.Length; i++)
	{
		MigrateCourse course;
		g_Courses.GetArray(i, course);
		if (course.keep)
		{
			keptCourses++;
		}
	}
	Migrate_Log("SUMMARY map courses: %d in input, %d kept.", g_Courses.Length, keptCourses);
}

static void SummarizePlayers()
{
	int kept = 0;
	for (int i = 0; i < g_Players.Length; i++)
	{
		MigratePlayer player;
		g_Players.GetArray(i, player);
		if (player.keep)
		{
			kept++;
		}
	}
	Migrate_Log("SUMMARY players: %d in input, %d kept, %d purged.", g_Players.Length, kept, g_Players.Length - kept);
}

static void SummarizeTimes()
{
	int kept = 0;
	for (int i = 0; i < g_Times.Length; i++)
	{
		MigrateTime time;
		g_Times.GetArray(i, time);
		if (time.keep)
		{
			kept++;
		}
	}
	Migrate_Log("SUMMARY times: %d in input, %d kept, %d dropped with deleted maps or hanging references.", g_Times.Length, kept, g_Times.Length - kept);
	SummarizeTimeReplays(kept);
}

static void SummarizeTimeReplays(int kept)
{
	int withReplay = 0;
	for (int i = 0; i < g_Times.Length; i++)
	{
		MigrateTime time;
		g_Times.GetArray(i, time);
		if (time.replayIndex != -1)
		{
			withReplay++;
		}
	}
	Migrate_Log("SUMMARY time replays: %d of the %d kept times have a replay, %d do not.", withReplay, kept, kept - withReplay);
}

static void SummarizeReplays()
{
	int counts[9];
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
	Migrate_Log("SUMMARY replays: %d files scanned; %d matched a migrated time, %d unmatched (no time), %d duplicates of another file, %d matched a time that is not migrated, %d unknown map, %d unknown course, %d unknown player, %d unreadable, %d unsupported type.",
		g_Replays.Length, counts[1], counts[0], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8]);
	Migrate_Log("SUMMARY imports: %d replays queued for upload (%d bytes).", imported, bytes);
}
