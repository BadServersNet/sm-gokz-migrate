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
	return true;
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
	if (gB_OutputHasRankedPool)
	{
		QueryBegin("INSERT INTO Maps (MapID, Name, LastPlayed, Created, InRankedPool) VALUES ");
	}
	else
	{
		QueryBegin("INSERT INTO Maps (MapID, Name, LastPlayed, Created) VALUES ");
	}

	int batched = 0;
	while (g_Cursor < g_Maps.Length && batched < MIGRATE_INSERT_BATCH && QueryHasRoom())
	{
		MigrateMap map;
		g_Maps.GetArray(g_Cursor, map);
		g_Cursor++;
		if (!IsMapInserted(map))
		{
			continue;
		}
		char name[136];
		char lastPlayed[32];
		char created[32];
		SqlString(gH_OutputDB, map.targetName, false, name, sizeof(name));
		SqlTimestamp(map.lastPlayed, lastPlayed, sizeof(lastPlayed));
		SqlCreated(map.created, created, sizeof(created));
		if (gB_OutputHasRankedPool)
		{
			QueryAppend("%s(%d, %s, %s, %s, %d)", batched > 0 ? "," : "", map.mapID, name, lastPlayed, created, map.inRankedPool);
		}
		else
		{
			QueryAppend("%s(%d, %s, %s, %s)", batched > 0 ? "," : "", map.mapID, name, lastPlayed, created);
		}
		batched++;
	}
	return FlushBatch("Maps", batched, g_Cursor >= g_Maps.Length);
}

bool Step_InsertCourses()
{
	QueryBegin("INSERT INTO MapCourses (MapCourseID, MapID, Course, Created) VALUES ");
	int batched = 0;
	while (g_Cursor < g_Courses.Length && batched < MIGRATE_INSERT_BATCH && QueryHasRoom())
	{
		MigrateCourse course;
		g_Courses.GetArray(g_Cursor, course);
		g_Cursor++;
		if (!course.keep)
		{
			continue;
		}
		char created[32];
		SqlCreated(course.created, created, sizeof(created));
		QueryAppend("%s(%d, %d, %d, %s)", batched > 0 ? "," : "", course.mapCourseID, course.targetMapID, course.course, created);
		batched++;
	}
	return FlushBatch("MapCourses", batched, g_Cursor >= g_Courses.Length);
}

bool Step_InsertTimes()
{
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
		char created[32];
		SqlCreated(time.created, created, sizeof(created));
		QueryAppend("%s(%d, %d, %d, %d, %d, %d, %d, %s)", batched > 0 ? "," : "", time.timeID, time.steamID, time.targetMapCourseID, time.mode, time.style, time.runTime, time.teleports, created);
		batched++;
	}
	return FlushBatch("Times", batched, g_Cursor >= g_Times.Length);
}

bool Step_InsertJumps()
{
	QueryBegin("INSERT INTO Jumpstats (JumpID, SteamID32, JumpType, Mode, Distance, IsBlockJump, Block, Strafes, Sync, Pre, Max, Airtime, Created) VALUES ");
	int batched = 0;
	while (g_Cursor < g_Jumps.Length && batched < MIGRATE_INSERT_BATCH && QueryHasRoom())
	{
		MigrateJump jump;
		g_Jumps.GetArray(g_Cursor, jump);
		g_Cursor++;
		if (!jump.keep)
		{
			continue;
		}
		char created[32];
		SqlCreated(jump.created, created, sizeof(created));
		QueryAppend("%s(%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s)", batched > 0 ? "," : "", jump.jumpID, jump.steamID, jump.jumpType, jump.mode, jump.distance, jump.isBlockJump, jump.block, jump.strafes, jump.sync, jump.pre, jump.max, jump.airtime, created);
		batched++;
	}
	return FlushBatch("Jumpstats", batched, g_Cursor >= g_Jumps.Length);
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
	Migrate_Log("Inserted batch %d into %s (%d rows, %d bytes).", g_BatchNumber, table, batched, QueryLength());
	return finished;
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
			QueryAppend("%s(%d, %d, %f, %f, %f, %d, %d)", batched > 0 ? "," : "", position.steamID, position.targetMapID, position.x, position.y, position.z, position.course, position.isStart);
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
			QueryAppend("%s(%d, %d, %f, %f, %f, %f, %f)", batched > 0 ? "," : "", position.steamID, position.targetMapID, position.x, position.y, position.z, position.angle0, position.angle1);
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
