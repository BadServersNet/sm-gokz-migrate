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
		ReportLine(report, "%d,%s,%s,%d,%s,%d,%d,%s", map.mapID, name, status, map.targetMapID, targetName, map.timeCount, map.validated ? 1 : 0, note);
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

bool Step_Summary()
{
	CloseReports();
	SummarizeMaps();
	SummarizePlayers();
	SummarizeTimes();
	SummarizeJumps();
	Migrate_Log("Mode: %s.", gB_DryRun ? "DRY RUN, nothing was written; rerun with sm_gokz_migrate_run to apply" : "REAL RUN, the gokz database was rebuilt; run sm_gokz_migrate_replays_run to import the legacy replays");
	Migrate_Log("Reports were written next to the log with the prefix %s", gC_ReportPrefix);
	return true;
}



// =====[ PRIVATE ]=====

static void GetMapStatusName(MapStatus status, char[] buffer, int maxlength)
{
	static const char names[][] = { "global", "renamed", "merged", "deleted", "hanging" };
	strcopy(buffer, maxlength, names[view_as<int>(status)]);
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
}

static void SummarizeJumps()
{
	int kept = 0;
	for (int i = 0; i < g_Jumps.Length; i++)
	{
		MigrateJump jump;
		g_Jumps.GetArray(i, jump);
		if (jump.keep)
		{
			kept++;
		}
	}
	Migrate_Log("SUMMARY jumps: %d in input, %d kept, %d dropped for hanging references.", g_Jumps.Length, kept, g_Jumps.Length - kept);
}
