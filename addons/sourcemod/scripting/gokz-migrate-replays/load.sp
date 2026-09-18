// =====[ STEPS ]=====

bool Step_LoadMaps()
{
	char query[256];
	FormatEx(query, sizeof(query), "SELECT MapID, Name FROM Maps WHERE MapID > %d ORDER BY MapID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		LegacyMap map;
		map.mapID = results.FetchInt(0);
		results.FetchString(1, map.name, sizeof(LegacyMap::name));
		int index = g_Maps.PushArray(map);

		char key[64];
		String_ToLower(map.name, key, sizeof(key));
		g_MapIndexByName.SetValue(key, index);
		IntKey(map.mapID, key, sizeof(key));
		g_MapIndexByID.SetValue(key, index);
		g_LastID = map.mapID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d legacy maps (%d total).", rows, g_Maps.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadCourses()
{
	char query[256];
	FormatEx(query, sizeof(query), "SELECT MapCourseID, MapID, Course FROM MapCourses WHERE MapCourseID > %d ORDER BY MapCourseID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		LegacyCourse course;
		course.mapCourseID = results.FetchInt(0);
		course.mapID = results.FetchInt(1);
		course.course = results.FetchInt(2);
		int index = g_Courses.PushArray(course);

		char key[64];
		CourseKey(course.mapID, course.course, key, sizeof(key));
		g_CourseIndexByKey.SetValue(key, index);
		IntKey(course.mapCourseID, key, sizeof(key));
		g_CourseIndexByID.SetValue(key, index);
		g_LastID = course.mapCourseID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d legacy map courses (%d total).", rows, g_Courses.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadPlayers()
{
	char query[256];
	FormatEx(query, sizeof(query), "SELECT SteamID32 FROM Players WHERE SteamID32 > %d ORDER BY SteamID32 LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		int steamID = results.FetchInt(0);
		char key[32];
		IntKey(steamID, key, sizeof(key));
		g_PlayerIDs.SetValue(key, 1);
		g_LastID = steamID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d legacy players (%d total).", rows, g_PlayerIDs.Size);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadTimes()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT TimeID, SteamID32, MapCourseID, Mode, Style, RunTime, Teleports, UNIX_TIMESTAMP(Created) FROM Times WHERE TimeID > %d ORDER BY TimeID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		LegacyTime time;
		time.timeID = results.FetchInt(0);
		time.steamID = results.FetchInt(1);
		time.mapCourseID = results.FetchInt(2);
		time.mode = results.FetchInt(3);
		time.style = results.FetchInt(4);
		time.runTime = results.FetchInt(5);
		time.teleports = results.FetchInt(6);
		time.created = results.FetchInt(7);
		time.replayIndex = -1;
		char key[64];
		TimeKey(time.steamID, time.mapCourseID, time.mode, time.style, time.runTime, key, sizeof(key));
		int index = g_Times.Length;
		time.nextIndex = ChainIndex(g_TimeIndexesByKey, key, index);
		g_Times.PushArray(time);
		g_LastID = time.timeID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d legacy times (%d total).", rows, g_Times.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadJumps()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT JumpID, SteamID32, JumpType, Mode, Distance, IsBlockJump, Block, UNIX_TIMESTAMP(Created) FROM Jumpstats WHERE JumpID > %d ORDER BY JumpID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		LegacyJump jump;
		jump.jumpID = results.FetchInt(0);
		jump.steamID = results.FetchInt(1);
		jump.jumpType = results.FetchInt(2);
		jump.mode = results.FetchInt(3);
		jump.distance = results.FetchInt(4);
		jump.isBlockJump = results.FetchInt(5);
		jump.block = results.FetchInt(6);
		jump.created = results.FetchInt(7);
		jump.replayIndex = -1;
		char key[64];
		JumpKey(jump.steamID, jump.jumpType, jump.mode, jump.distance, jump.block, key, sizeof(key));
		int index = g_Jumps.Length;
		jump.nextIndex = ChainIndex(g_JumpIndexesByKey, key, index);
		g_Jumps.PushArray(jump);
		g_LastID = jump.jumpID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d legacy jumps (%d total).", rows, g_Jumps.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadMigratedTimes()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT t.TimeID, m.Name FROM Times t JOIN MapCourses c ON c.MapCourseID = t.MapCourseID JOIN Maps m ON m.MapID = c.MapID WHERE t.TimeID > %d ORDER BY t.TimeID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_OutputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		int timeID = results.FetchInt(0);
		char mapName[64];
		results.FetchString(1, mapName, sizeof(mapName));
		char key[32];
		IntKey(timeID, key, sizeof(key));
		g_MigratedTimeMaps.SetString(key, mapName);
		g_LastID = timeID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d migrated times (%d total).", rows, g_MigratedTimeMaps.Size);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadMigratedJumps()
{
	char query[256];
	FormatEx(query, sizeof(query), "SELECT JumpID FROM Jumpstats WHERE JumpID > %d ORDER BY JumpID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_OutputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		int jumpID = results.FetchInt(0);
		char key[32];
		IntKey(jumpID, key, sizeof(key));
		g_MigratedJumpIDs.SetValue(key, 1);
		g_LastID = jumpID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d migrated jumps (%d total).", rows, g_MigratedJumpIDs.Size);
	return rows < MIGRATE_PAGE_SIZE;
}



// =====[ PUBLIC ]=====

void CourseKey(int mapID, int course, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "%d_%d", mapID, course);
}

void TimeKey(int steamID, int mapCourseID, int mode, int style, int runTime, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "%d_%d_%d_%d_%d", steamID, mapCourseID, mode, style, runTime);
}

void JumpKey(int steamID, int jumpType, int mode, int distance, int block, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "%d_%d_%d_%d_%d", steamID, jumpType, mode, distance, block);
}

int FindMapIndexByID(int mapID)
{
	char key[32];
	IntKey(mapID, key, sizeof(key));
	int index;
	if (!g_MapIndexByID.GetValue(key, index))
	{
		return -1;
	}
	return index;
}

int FindMapIndexByName(const char[] name)
{
	char key[64];
	String_ToLower(name, key, sizeof(key));
	int index;
	if (!g_MapIndexByName.GetValue(key, index))
	{
		return -1;
	}
	return index;
}

int FindCourseIndexByID(int mapCourseID)
{
	char key[32];
	IntKey(mapCourseID, key, sizeof(key));
	int index;
	if (!g_CourseIndexByID.GetValue(key, index))
	{
		return -1;
	}
	return index;
}

int FindCourseIndex(int mapID, int course)
{
	char key[64];
	CourseKey(mapID, course, key, sizeof(key));
	int index;
	if (!g_CourseIndexByKey.GetValue(key, index))
	{
		return -1;
	}
	return index;
}

bool IsKnownPlayer(int steamID)
{
	char key[32];
	IntKey(steamID, key, sizeof(key));
	int value;
	return g_PlayerIDs.GetValue(key, value);
}

bool FindMigratedTimeMap(int timeID, char[] buffer, int maxlength)
{
	char key[32];
	IntKey(timeID, key, sizeof(key));
	return g_MigratedTimeMaps.GetString(key, buffer, maxlength);
}

bool IsMigratedJump(int jumpID)
{
	char key[32];
	IntKey(jumpID, key, sizeof(key));
	int value;
	return g_MigratedJumpIDs.GetValue(key, value);
}
