// =====[ STEPS ]=====

bool Step_LoadMaps()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT MapID, Name, IFNULL(UNIX_TIMESTAMP(LastPlayed), -1), UNIX_TIMESTAMP(Created), %s FROM Maps WHERE MapID > %d ORDER BY MapID LIMIT %d", InputHasRankedPool() ? "InRankedPool" : "0", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		MigrateMap map;
		map.mapID = results.FetchInt(0);
		results.FetchString(1, map.name, sizeof(MigrateMap::name));
		map.lastPlayed = results.FetchInt(2);
		map.created = results.FetchInt(3);
		map.inRankedPool = results.FetchInt(4);
		map.targetMapID = map.mapID;
		strcopy(map.targetName, sizeof(MigrateMap::targetName), map.name);
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
	Migrate_Log("Loaded %d maps (%d total).", rows, g_Maps.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadCourses()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT MapCourseID, MapID, Course, UNIX_TIMESTAMP(Created) FROM MapCourses WHERE MapCourseID > %d ORDER BY MapCourseID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		MigrateCourse course;
		course.mapCourseID = results.FetchInt(0);
		course.mapID = results.FetchInt(1);
		course.course = results.FetchInt(2);
		course.created = results.FetchInt(3);
		course.targetMapID = course.mapID;
		course.targetMapCourseID = course.mapCourseID;
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
	Migrate_Log("Loaded %d map courses (%d total).", rows, g_Courses.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadPlayers()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT SteamID32, Alias, Country, IP, Cheater, IFNULL(UNIX_TIMESTAMP(LastPlayed), -1), UNIX_TIMESTAMP(Created) FROM Players WHERE SteamID32 > %d ORDER BY SteamID32 LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		MigratePlayer player;
		player.steamID = results.FetchInt(0);
		player.aliasNull = results.IsFieldNull(1);
		results.FetchString(1, player.alias, sizeof(MigratePlayer::alias));
		player.countryNull = results.IsFieldNull(2);
		results.FetchString(2, player.country, sizeof(MigratePlayer::country));
		player.ipNull = results.IsFieldNull(3);
		results.FetchString(3, player.ip, sizeof(MigratePlayer::ip));
		player.cheater = results.FetchInt(4);
		player.lastPlayed = results.FetchInt(5);
		player.created = results.FetchInt(6);
		int index = g_Players.PushArray(player);

		char key[32];
		IntKey(player.steamID, key, sizeof(key));
		g_PlayerIndexByID.SetValue(key, index);
		g_LastID = player.steamID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d players (%d total).", rows, g_Players.Length);
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
		MigrateTime time;
		time.timeID = results.FetchInt(0);
		time.steamID = results.FetchInt(1);
		time.mapCourseID = results.FetchInt(2);
		time.mode = results.FetchInt(3);
		time.style = results.FetchInt(4);
		time.runTime = results.FetchInt(5);
		time.teleports = results.FetchInt(6);
		time.created = results.FetchInt(7);
		g_Times.PushArray(time);
		g_LastID = time.timeID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d times (%d total).", rows, g_Times.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadJumps()
{
	char query[512];
	FormatEx(query, sizeof(query), "SELECT JumpID, SteamID32, JumpType, Mode, Distance, IsBlockJump, Block, Strafes, Sync, Pre, Max, Airtime, UNIX_TIMESTAMP(Created) FROM Jumpstats WHERE JumpID > %d ORDER BY JumpID LIMIT %d", g_LastID, MIGRATE_PAGE_SIZE);
	DBResultSet results = Migrate_Query(gH_InputDB, query);
	if (results == null)
	{
		return false;
	}

	int rows = 0;
	while (results.FetchRow())
	{
		MigrateJump jump;
		jump.jumpID = results.FetchInt(0);
		jump.steamID = results.FetchInt(1);
		jump.jumpType = results.FetchInt(2);
		jump.mode = results.FetchInt(3);
		jump.distance = results.FetchInt(4);
		jump.isBlockJump = results.FetchInt(5);
		jump.block = results.FetchInt(6);
		jump.strafes = results.FetchInt(7);
		jump.sync = results.FetchInt(8);
		jump.pre = results.FetchInt(9);
		jump.max = results.FetchInt(10);
		jump.airtime = results.FetchInt(11);
		jump.created = results.FetchInt(12);
		g_Jumps.PushArray(jump);
		g_LastID = jump.jumpID;
		rows++;
	}
	delete results;
	Migrate_Log("Loaded %d jumps (%d total).", rows, g_Jumps.Length);
	return rows < MIGRATE_PAGE_SIZE;
}

bool Step_LoadPositions()
{
	if (!LoadVBPositions())
	{
		return false;
	}
	return LoadStartPositions();
}



// =====[ PUBLIC ]=====

void CourseKey(int mapID, int course, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "%d_%d", mapID, course);
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

int FindPlayerIndex(int steamID)
{
	char key[32];
	IntKey(steamID, key, sizeof(key));
	int index;
	if (!g_PlayerIndexByID.GetValue(key, index))
	{
		return -1;
	}
	return index;
}



// =====[ PRIVATE ]=====

static bool InputHasRankedPool()
{
	static int cached = -1;
	if (cached != -1)
	{
		return cached == 1;
	}
	int count = Migrate_FetchScalarInt(gH_InputDB, "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='Maps' AND COLUMN_NAME='InRankedPool'");
	cached = count > 0 ? 1 : 0;
	return cached == 1;
}

static bool LoadVBPositions()
{
	DBResultSet results = Migrate_Query(gH_InputDB, "SELECT SteamID32, MapID, X, Y, Z, Course, IsStart FROM VBPosition");
	if (results == null)
	{
		return false;
	}
	while (results.FetchRow())
	{
		MigrateVBPosition position;
		position.steamID = results.FetchInt(0);
		position.mapID = results.FetchInt(1);
		position.x = results.FetchFloat(2);
		position.y = results.FetchFloat(3);
		position.z = results.FetchFloat(4);
		position.course = results.FetchInt(5);
		position.isStart = results.FetchInt(6);
		position.targetMapID = position.mapID;
		g_VBPositions.PushArray(position);
	}
	delete results;
	Migrate_Log("Loaded %d virtual button positions.", g_VBPositions.Length);
	return true;
}

static bool LoadStartPositions()
{
	DBResultSet results = Migrate_Query(gH_InputDB, "SELECT SteamID32, MapID, X, Y, Z, Angle0, Angle1 FROM StartPosition");
	if (results == null)
	{
		return false;
	}
	while (results.FetchRow())
	{
		MigrateStartPosition position;
		position.steamID = results.FetchInt(0);
		position.mapID = results.FetchInt(1);
		position.x = results.FetchFloat(2);
		position.y = results.FetchFloat(3);
		position.z = results.FetchFloat(4);
		position.angle0 = results.FetchFloat(5);
		position.angle1 = results.FetchFloat(6);
		position.targetMapID = position.mapID;
		g_StartPositions.PushArray(position);
	}
	delete results;
	Migrate_Log("Loaded %d start positions.", g_StartPositions.Length);
	return true;
}
