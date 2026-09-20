#define MIGRATE_MAPS_PER_TICK 20



// =====[ STEPS ]=====

bool Step_WipeOutput()
{
	static const char tables[][] = { "Replays", "Times", "Jumpstats", "VBPosition", "StartPosition", "MapCourses", "Maps", "Players" };
	Migrate_Log("Wiping the output database tables: Replays, Times, Jumpstats, VBPosition, StartPosition, MapCourses, Maps, Players.");
	for (int i = 0; i < sizeof(tables); i++)
	{
		char query[128];
		FormatEx(query, sizeof(query), "DELETE FROM %s", tables[i]);
		if (!Migrate_Exec(gH_OutputDB, query))
		{
			return false;
		}
		Migrate_Log("Wiped %s.", tables[i]);
	}
	if (!ResetAutoIncrements())
	{
		return false;
	}
	return CreateIDTables();
}

bool Step_InsertPlayers()
{
	QueryBegin("INSERT INTO Players (SteamID32, Alias, Country, IP, Cheater, LastPlayed, Created) VALUES ");
	int batched = 0;
	while (g_Cursor < g_Players.Length && batched < MIGRATE_INSERT_BATCH && QueryHasRoom())
	{
		MigratePlayer player;
		g_Players.GetArray(g_Cursor, player);
		g_Cursor++;
		if (!player.keep)
		{
			continue;
		}
		char alias[272];
		char country[400];
		char ip[48];
		char lastPlayed[32];
		char created[32];
		SqlString(gH_OutputDB, player.alias, player.aliasNull, alias, sizeof(alias));
		SqlString(gH_OutputDB, player.country, player.countryNull, country, sizeof(country));
		SqlString(gH_OutputDB, player.ip, player.ipNull, ip, sizeof(ip));
		SqlTimestamp(player.lastPlayed, lastPlayed, sizeof(lastPlayed));
		SqlCreated(player.created, created, sizeof(created));
		QueryAppend("%s(%d, %s, %s, %s, %d, %s, %s)", batched > 0 ? "," : "", player.steamID, alias, country, ip, player.cheater, lastPlayed, created);
		batched++;
	}
	return FlushBatch("Players", batched, g_Cursor >= g_Players.Length);
}

bool Step_InsertMaps()
{
	int end = IntMin(g_Cursor + MIGRATE_MAPS_PER_TICK, g_Maps.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		if (!MoveMap(map))
		{
			return false;
		}
	}
	g_Cursor = end;
	return g_Cursor >= g_Maps.Length;
}

bool Step_InsertTimes()
{
	int start = g_Cursor;
	QueryBegin("INSERT INTO Times (TimeID, SteamID32, MapCourseID, Mode, Style, RunTime, Teleports, Created) VALUES ");
	int batched = 0;
	while (g_Cursor < g_Times.Length && batched < MIGRATE_INSERT_BATCH && QueryHasRoom())
	{
		MigrateTime time;
		g_Times.GetArray(g_Cursor, time);
		g_Cursor++;
		if (!time.keep)
		{
			continue;
		}
		int newMapCourseID = GetNewMapCourseID(time.targetMapCourseID);
		char created[32];
		SqlCreated(time.created, created, sizeof(created));
		QueryAppend("%s(%d, %d, %d, %d, %d, %d, %d, %s)", batched > 0 ? "," : "", time.newTimeID, time.steamID, newMapCourseID, time.mode, time.style, time.runTime, time.teleports, created);
		batched++;
	}
	int end = g_Cursor;
	bool finished = end >= g_Times.Length;
	if (batched == 0)
	{
		return finished;
	}
	if (!FlushBatch("Times", batched, true))
	{
		return false;
	}
	if (!InsertTimeIDs(start, end))
	{
		return false;
	}
	return finished;
}

bool Step_InsertPositions()
{
	if (!InsertVBPositions())
	{
		return false;
	}
	return InsertStartPositions();
}



// =====[ PRIVATE ]=====

static bool FlushBatch(const char[] table, int batched, bool finished)
{
	if (batched == 0)
	{
		return finished;
	}
	g_BatchNumber++;
	if (!QueryFlush(gH_OutputDB))
	{
		return false;
	}
	Migrate_Detail("Inserted batch %d into %s (%d rows, %d bytes).", g_BatchNumber, table, batched, QueryLength());
	return finished;
}

static bool ResetAutoIncrements()
{
	static const char tables[][] = { "Replays", "Times", "Jumpstats", "MapCourses", "Maps" };
	for (int i = 0; i < sizeof(tables); i++)
	{
		char query[128];
		FormatEx(query, sizeof(query), "ALTER TABLE %s AUTO_INCREMENT = 1", tables[i]);
		if (!Migrate_Exec(gH_OutputDB, query))
		{
			return false;
		}
		Migrate_Log("Reset the AUTO_INCREMENT of %s.", tables[i]);
	}
	return true;
}

static bool CreateIDTables()
{
	static const char tables[][] = { "MigrateMapIDs", "MigrateCourseIDs", "MigrateTimeIDs" };
	static const char columns[][] = { "MapID", "MapCourseID", "TimeID" };
	for (int i = 0; i < sizeof(tables); i++)
	{
		char query[512];
		FormatEx(query, sizeof(query), "DROP TABLE IF EXISTS %s", tables[i]);
		if (!Migrate_Exec(gH_OutputDB, query))
		{
			return false;
		}
		FormatEx(query, sizeof(query), "CREATE TABLE %s (Old%s INTEGER UNSIGNED NOT NULL, New%s INTEGER UNSIGNED NOT NULL, CONSTRAINT PK_%s PRIMARY KEY (Old%s), INDEX IX_%s_New (New%s))", tables[i], columns[i], columns[i], tables[i], columns[i], tables[i], columns[i]);
		if (!Migrate_Exec(gH_OutputDB, query))
		{
			return false;
		}
		Migrate_Log("Created the %s table that maps every Old%s to its New%s.", tables[i], columns[i], columns[i]);
	}
	return true;
}

static bool MoveMap(MigrateMap map)
{
	if (map.newMapID == 0)
	{
		return true;
	}
	if (IsMapInserted(map))
	{
		if (!InsertMap(map))
		{
			return false;
		}
		if (!InsertMapCourses(map))
		{
			return false;
		}
	}
	if (!InsertMapID(map))
	{
		return false;
	}
	return InsertCourseIDs(map);
}

static bool InsertMap(MigrateMap map)
{
	char name[136];
	char lastPlayed[32];
	char created[32];
	SqlString(gH_OutputDB, map.targetName, false, name, sizeof(name));
	SqlTimestamp(map.lastPlayed, lastPlayed, sizeof(lastPlayed));
	SqlCreated(map.created, created, sizeof(created));
	if (gB_OutputHasRankedPool)
	{
		QueryBegin("INSERT INTO Maps (MapID, Name, LastPlayed, Created, InRankedPool) VALUES ");
		QueryAppend("(%d, %s, %s, %s, %d)", map.newMapID, name, lastPlayed, created, map.inRankedPool);
	}
	else
	{
		QueryBegin("INSERT INTO Maps (MapID, Name, LastPlayed, Created) VALUES ");
		QueryAppend("(%d, %s, %s, %s)", map.newMapID, name, lastPlayed, created);
	}
	if (!QueryFlush(gH_OutputDB))
	{
		return false;
	}
	Migrate_Detail("Moved map %s: MapID %d becomes MapID %d.", map.targetName, map.mapID, map.newMapID);
	return true;
}

static bool InsertMapCourses(MigrateMap map)
{
	QueryBegin("INSERT INTO MapCourses (MapCourseID, MapID, Course, Created) VALUES ");
	int batched = 0;
	for (int courseNumber = 0; courseNumber < GOKZ_MAX_COURSES; courseNumber++)
	{
		int courseIndex = FindCourseIndex(map.mapID, courseNumber);
		if (courseIndex == -1)
		{
			continue;
		}
		MigrateCourse course;
		g_Courses.GetArray(courseIndex, course);
		if (!course.keep)
		{
			continue;
		}
		char created[32];
		SqlCreated(course.created, created, sizeof(created));
		QueryAppend("%s(%d, %d, %d, %s)", batched > 0 ? "," : "", course.newMapCourseID, map.newMapID, course.course, created);
		batched++;
	}
	if (batched == 0)
	{
		return true;
	}
	return QueryFlush(gH_OutputDB);
}

static bool InsertMapID(MigrateMap map)
{
	QueryBegin("INSERT INTO MigrateMapIDs (OldMapID, NewMapID) VALUES ");
	QueryAppend("(%d, %d)", map.mapID, map.newMapID);
	return QueryFlush(gH_OutputDB);
}

static bool InsertCourseIDs(MigrateMap map)
{
	QueryBegin("INSERT INTO MigrateCourseIDs (OldMapCourseID, NewMapCourseID) VALUES ");
	int batched = 0;
	for (int courseNumber = 0; courseNumber < GOKZ_MAX_COURSES; courseNumber++)
	{
		int courseIndex = FindCourseIndex(map.mapID, courseNumber);
		if (courseIndex == -1)
		{
			continue;
		}
		MigrateCourse course;
		g_Courses.GetArray(courseIndex, course);
		bool moved = course.mapID == map.mapID && course.newMapCourseID != 0;
		if (!moved)
		{
			continue;
		}
		QueryAppend("%s(%d, %d)", batched > 0 ? "," : "", course.mapCourseID, course.newMapCourseID);
		batched++;
	}
	if (batched == 0)
	{
		return true;
	}
	return QueryFlush(gH_OutputDB);
}

static bool InsertTimeIDs(int start, int end)
{
	QueryBegin("INSERT INTO MigrateTimeIDs (OldTimeID, NewTimeID) VALUES ");
	int batched = 0;
	for (int i = start; i < end; i++)
	{
		MigrateTime time;
		g_Times.GetArray(i, time);
		if (!time.keep)
		{
			continue;
		}
		QueryAppend("%s(%d, %d)", batched > 0 ? "," : "", time.timeID, time.newTimeID);
		batched++;
	}
	return QueryFlush(gH_OutputDB);
}

static bool InsertVBPositions()
{
	int inserted = 0;
	int batchStart = 0;
	while (batchStart < g_VBPositions.Length)
	{
		QueryBegin("INSERT INTO VBPosition (SteamID32, MapID, X, Y, Z, Course, IsStart) VALUES ");
		int batched = 0;
		int end = IntMin(batchStart + MIGRATE_INSERT_BATCH, g_VBPositions.Length);
		for (int i = batchStart; i < end; i++)
		{
			MigrateVBPosition position;
			g_VBPositions.GetArray(i, position);
			if (!position.keep)
			{
				continue;
			}
			int newMapID = GetNewMapID(position.targetMapID);
			QueryAppend("%s(%d, %d, %f, %f, %f, %d, %d)", batched > 0 ? "," : "", position.steamID, newMapID, position.x, position.y, position.z, position.course, position.isStart);
			batched++;
		}
		batchStart = end;
		if (batched == 0)
		{
			continue;
		}
		if (!QueryFlush(gH_OutputDB))
		{
			return false;
		}
		inserted += batched;
	}
	Migrate_Log("Inserted %d virtual button positions.", inserted);
	return true;
}

static bool InsertStartPositions()
{
	int inserted = 0;
	int batchStart = 0;
	while (batchStart < g_StartPositions.Length)
	{
		QueryBegin("INSERT INTO StartPosition (SteamID32, MapID, X, Y, Z, Angle0, Angle1) VALUES ");
		int batched = 0;
		int end = IntMin(batchStart + MIGRATE_INSERT_BATCH, g_StartPositions.Length);
		for (int i = batchStart; i < end; i++)
		{
			MigrateStartPosition position;
			g_StartPositions.GetArray(i, position);
			if (!position.keep)
			{
				continue;
			}
			int newMapID = GetNewMapID(position.targetMapID);
			QueryAppend("%s(%d, %d, %f, %f, %f, %f, %f)", batched > 0 ? "," : "", position.steamID, newMapID, position.x, position.y, position.z, position.angle0, position.angle1);
			batched++;
		}
		batchStart = end;
		if (batched == 0)
		{
			continue;
		}
		if (!QueryFlush(gH_OutputDB))
		{
			return false;
		}
		inserted += batched;
	}
	Migrate_Log("Inserted %d start positions.", inserted);
	return true;
}
