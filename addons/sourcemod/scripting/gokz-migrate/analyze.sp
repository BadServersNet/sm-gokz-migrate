#define MIGRATE_ANALYZE_BATCH 20000

static StringMap g_RenamedTargets;
static StringMap g_PositionKeys;



// =====[ STEPS ]=====

bool Step_AnalyzeMaps()
{
	delete g_RenamedTargets;
	g_RenamedTargets = new StringMap();

	int globalCount = 0;
	int renamedCount = 0;
	int mergedCount = 0;
	int deletedCount = 0;
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		ClassifyMap(i, map);
		g_Maps.SetArray(i, map);
		switch (map.status)
		{
			case MapStatus_Global: globalCount++;
			case MapStatus_Renamed: renamedCount++;
			case MapStatus_Merged: mergedCount++;
			case MapStatus_Deleted: deletedCount++;
		}
	}
	delete g_RenamedTargets;
	Migrate_Log("Maps: %d global, %d renamed, %d merged into another map, %d not global (will be deleted).", globalCount, renamedCount, mergedCount, deletedCount);
	return true;
}

bool Step_AnalyzeCourses()
{
	int orphaned = 0;
	int dropped = 0;
	int merged = 0;
	for (int i = 0; i < g_Courses.Length; i++)
	{
		MigrateCourse course;
		g_Courses.GetArray(i, course);
		int mapIndex = FindMapIndexByID(course.mapID);
		if (mapIndex == -1)
		{
			course.keep = false;
			orphaned++;
			Migrate_Detail("Hanging MapCourse %d references missing MapID %d.", course.mapCourseID, course.mapID);
			g_Courses.SetArray(i, course);
			continue;
		}

		MigrateMap map;
		g_Maps.GetArray(mapIndex, map);
		course.targetMapID = map.targetMapID;
		course.targetMapCourseID = course.mapCourseID;
		course.keep = map.status != MapStatus_Deleted;
		if (!course.keep)
		{
			dropped++;
		}
		if (map.status == MapStatus_Merged)
		{
			int existing = FindCourseIndex(map.targetMapID, course.course);
			if (existing != -1 && existing != i)
			{
				MigrateCourse target;
				g_Courses.GetArray(existing, target);
				course.targetMapCourseID = target.mapCourseID;
				course.keep = false;
				merged++;
				Migrate_Detail("MapCourse %d (%s course %d) merges into MapCourse %d of %s.", course.mapCourseID, map.name, course.course, target.mapCourseID, map.targetName);
			}
			else
			{
				RegisterCourseIndex(map.targetMapID, course.course, i);
			}
		}
		g_Courses.SetArray(i, course);
	}
	Migrate_Log("Map courses: %d total, %d orphaned, %d dropped with deleted maps, %d merged into renamed maps.", g_Courses.Length, orphaned, dropped, merged);
	return true;
}

bool Step_AnalyzeTimes()
{
	int end = IntMin(g_Cursor + MIGRATE_ANALYZE_BATCH, g_Times.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateTime time;
		g_Times.GetArray(i, time);
		AnalyzeTime(time);
		g_Times.SetArray(i, time);
	}
	g_Cursor = end;
	Migrate_Detail("Analyzed %d of %d times.", g_Cursor, g_Times.Length);
	return g_Cursor >= g_Times.Length;
}

bool Step_AnalyzePlayers()
{
	bool keepCheaters = gCV_gokz_migrate_keep_cheater_players.BoolValue;
	int kept = 0;
	int purged = 0;
	int cheatersWithoutData = 0;
	for (int i = 0; i < g_Players.Length; i++)
	{
		MigratePlayer player;
		g_Players.GetArray(i, player);
		bool hasData = player.timeCount > 0;
		bool cheaterOnly = !hasData && player.cheater != 0;
		if (cheaterOnly)
		{
			cheatersWithoutData++;
		}
		player.keep = hasData || (cheaterOnly && keepCheaters);
		g_Players.SetArray(i, player);
		if (player.keep)
		{
			kept++;
			continue;
		}
		purged++;
	}
	Migrate_Log("Players: %d total, %d kept, %d purged for having no times, %d flagged cheaters without data (%s).", g_Players.Length, kept, purged, cheatersWithoutData, keepCheaters ? "kept" : "purged");
	return true;
}

bool Step_AnalyzeHanging()
{
	int hangingCourses = 0;
	for (int i = 0; i < g_Courses.Length; i++)
	{
		MigrateCourse course;
		g_Courses.GetArray(i, course);
		if (!course.keep || course.timeCount > 0)
		{
			continue;
		}
		course.keep = false;
		g_Courses.SetArray(i, course);
		hangingCourses++;
		Migrate_Detail("Hanging MapCourse %d (MapID %d course %d) has no times and will not be migrated.", course.mapCourseID, course.mapID, course.course);
	}

	int hangingMaps = 0;
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		bool inserted = map.status == MapStatus_Global || map.status == MapStatus_Renamed;
		if (!inserted || map.timeCount > 0)
		{
			continue;
		}
		map.status = MapStatus_Hanging;
		g_Maps.SetArray(i, map);
		hangingMaps++;
		Migrate_Detail("Hanging map %s (MapID %d) has no times and will not be migrated.", map.name, map.mapID);
	}

	delete g_PositionKeys;
	g_PositionKeys = new StringMap();
	int vbKept = AnalyzeVBPositions();
	int startKept = AnalyzeStartPositions();
	delete g_PositionKeys;

	Migrate_Log("Hanging records: %d courses without times, %d maps without times.", hangingCourses, hangingMaps);
	Migrate_Log("Positions: %d of %d virtual button positions and %d of %d start positions kept.", vbKept, g_VBPositions.Length, startKept, g_StartPositions.Length);
	return true;
}



// =====[ PUBLIC ]=====

bool IsMapInserted(MigrateMap map)
{
	return map.status == MapStatus_Global || map.status == MapStatus_Renamed;
}



// =====[ PRIVATE ]=====

static void ClassifyMap(int index, MigrateMap map)
{
	char lower[64];
	String_ToLower(map.name, lower, sizeof(lower));

	char newName[64];
	bool renamed = g_Renames.GetString(lower, newName, sizeof(newName));
	if (renamed)
	{
		ClassifyRenamedMap(index, map, newName);
		return;
	}

	bool validated;
	if (IsGlobalMap(lower, validated))
	{
		map.status = MapStatus_Global;
		map.validated = validated;
		return;
	}

	map.status = MapStatus_Deleted;
	FindRenameCandidates(lower, map.note, sizeof(MigrateMap::note));
	if (map.note[0] == '\0')
	{
		Migrate_Detail("Map %s (MapID %d) is not on the global map list and has no similar global map.", map.name, map.mapID);
		return;
	}
	Migrate_Detail("Map %s (MapID %d) is not on the global map list; possible renames: %s. Add it to the rename file to migrate it instead of deleting it.", map.name, map.mapID, map.note);
}

static void ClassifyRenamedMap(int index, MigrateMap map, const char[] newName)
{
	bool validated;
	if (!IsGlobalMap(newName, validated))
	{
		map.status = MapStatus_Deleted;
		FormatEx(map.note, sizeof(MigrateMap::note), "rename target %s is not global", newName);
		Migrate_Log("Map %s (MapID %d) is renamed to %s but that map is not global either; it will be deleted.", map.name, map.mapID, newName);
		return;
	}

	map.validated = validated;
	strcopy(map.targetName, sizeof(MigrateMap::targetName), newName);
	int existing = FindMapIndexByName(newName);
	if (existing == -1)
	{
		int renamedIndex;
		existing = g_RenamedTargets.GetValue(newName, renamedIndex) ? renamedIndex : -1;
	}
	if (existing != -1 && existing != index)
	{
		MigrateMap target;
		g_Maps.GetArray(existing, target);
		map.status = MapStatus_Merged;
		map.targetMapID = target.mapID;
		Migrate_Log("Map %s (MapID %d) merges into %s (MapID %d).", map.name, map.mapID, target.name, target.mapID);
		return;
	}

	map.status = MapStatus_Renamed;
	g_RenamedTargets.SetValue(newName, index);
	Migrate_Log("Map %s (MapID %d) is renamed to %s.", map.name, map.mapID, newName);
}

static void AnalyzeTime(MigrateTime time)
{
	time.keep = false;
	time.targetMapCourseID = time.mapCourseID;

	int courseIndex = FindCourseIndexByID(time.mapCourseID);
	if (courseIndex == -1)
	{
		Migrate_Detail("Hanging TimeID %d references missing MapCourseID %d.", time.timeID, time.mapCourseID);
		return;
	}
	MigrateCourse course;
	g_Courses.GetArray(courseIndex, course);
	int mapIndex = FindMapIndexByID(course.mapID);
	if (mapIndex == -1)
	{
		return;
	}
	MigrateMap map;
	g_Maps.GetArray(mapIndex, map);
	if (map.status == MapStatus_Deleted)
	{
		return;
	}

	int playerIndex = FindPlayerIndex(time.steamID);
	if (playerIndex == -1)
	{
		Migrate_Detail("Hanging TimeID %d references missing SteamID32 %d.", time.timeID, time.steamID);
		return;
	}

	time.keep = true;
	time.targetMapCourseID = course.targetMapCourseID;
	CountTimeOnCourse(course.targetMapCourseID);
	CountTimeOnMap(course.targetMapID);
	CountTimeOnPlayer(playerIndex);
}

static void CountTimeOnCourse(int mapCourseID)
{
	int courseIndex = FindCourseIndexByID(mapCourseID);
	if (courseIndex == -1)
	{
		return;
	}
	MigrateCourse course;
	g_Courses.GetArray(courseIndex, course);
	course.timeCount++;
	g_Courses.SetArray(courseIndex, course);
}

static void CountTimeOnMap(int mapID)
{
	int mapIndex = FindMapIndexByID(mapID);
	if (mapIndex == -1)
	{
		return;
	}
	MigrateMap map;
	g_Maps.GetArray(mapIndex, map);
	map.timeCount++;
	g_Maps.SetArray(mapIndex, map);
}

static void CountTimeOnPlayer(int playerIndex)
{
	MigratePlayer player;
	g_Players.GetArray(playerIndex, player);
	player.timeCount++;
	g_Players.SetArray(playerIndex, player);
}

static bool IsPositionOwnerKept(int steamID, int mapID, int &targetMapID)
{
	int playerIndex = FindPlayerIndex(steamID);
	if (playerIndex == -1)
	{
		return false;
	}
	MigratePlayer player;
	g_Players.GetArray(playerIndex, player);
	if (!player.keep)
	{
		return false;
	}

	int mapIndex = FindMapIndexByID(mapID);
	if (mapIndex == -1)
	{
		return false;
	}
	MigrateMap map;
	g_Maps.GetArray(mapIndex, map);
	int targetIndex = FindMapIndexByID(map.targetMapID);
	if (targetIndex == -1)
	{
		return false;
	}
	MigrateMap target;
	g_Maps.GetArray(targetIndex, target);
	if (!IsMapInserted(target))
	{
		return false;
	}
	targetMapID = target.mapID;
	return true;
}

static int AnalyzeVBPositions()
{
	int kept = 0;
	for (int i = 0; i < g_VBPositions.Length; i++)
	{
		MigrateVBPosition position;
		g_VBPositions.GetArray(i, position);
		position.keep = IsPositionOwnerKept(position.steamID, position.mapID, position.targetMapID);
		if (position.keep)
		{
			char key[64];
			FormatEx(key, sizeof(key), "vb_%d_%d_%d", position.steamID, position.targetMapID, position.isStart);
			position.keep = ClaimPositionKey(key);
		}
		g_VBPositions.SetArray(i, position);
		if (position.keep)
		{
			kept++;
		}
	}
	return kept;
}

static int AnalyzeStartPositions()
{
	int kept = 0;
	for (int i = 0; i < g_StartPositions.Length; i++)
	{
		MigrateStartPosition position;
		g_StartPositions.GetArray(i, position);
		position.keep = IsPositionOwnerKept(position.steamID, position.mapID, position.targetMapID);
		if (position.keep)
		{
			char key[64];
			FormatEx(key, sizeof(key), "sp_%d_%d", position.steamID, position.targetMapID);
			position.keep = ClaimPositionKey(key);
		}
		g_StartPositions.SetArray(i, position);
		if (position.keep)
		{
			kept++;
		}
	}
	return kept;
}

static bool ClaimPositionKey(const char[] key)
{
	int existing;
	if (g_PositionKeys.GetValue(key, existing))
	{
		return false;
	}
	g_PositionKeys.SetValue(key, 1);
	return true;
}
