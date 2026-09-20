static int g_NextMapID;
static int g_NextMapCourseID;
static int g_NextTimeID;



// =====[ STEPS ]=====

bool Step_AssignMapIDs()
{
	g_NextMapID = 1;
	g_NextMapCourseID = 1;
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		if (!IsMapInserted(map))
		{
			continue;
		}
		map.newMapID = g_NextMapID;
		g_NextMapID++;
		g_Maps.SetArray(i, map);
		AssignCourseIDs(map);
	}
	AssignMergedMapIDs();
	AssignMergedCourseIDs();
	if (!VerifyCourseIDs())
	{
		return false;
	}
	Migrate_Log("Assigned new MapIDs 1 to %d and new MapCourseIDs 1 to %d.", g_NextMapID - 1, g_NextMapCourseID - 1);
	return true;
}

bool Step_AssignTimeIDs()
{
	if (g_Cursor == 0)
	{
		g_NextTimeID = 1;
	}
	int end = IntMin(g_Cursor + MIGRATE_ANALYZE_BATCH, g_Times.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateTime time;
		g_Times.GetArray(i, time);
		if (!time.keep)
		{
			continue;
		}
		time.newTimeID = g_NextTimeID;
		g_NextTimeID++;
		g_Times.SetArray(i, time);
	}
	g_Cursor = end;
	bool finished = g_Cursor >= g_Times.Length;
	if (finished)
	{
		Migrate_Log("Assigned new TimeIDs 1 to %d.", g_NextTimeID - 1);
	}
	return finished;
}



// =====[ PUBLIC ]=====

int GetNewMapCourseID(int mapCourseID)
{
	int courseIndex = FindCourseIndexByID(mapCourseID);
	if (courseIndex == -1)
	{
		return 0;
	}
	MigrateCourse course;
	g_Courses.GetArray(courseIndex, course);
	return course.newMapCourseID;
}

int GetNewMapID(int mapID)
{
	int mapIndex = FindMapIndexByID(mapID);
	if (mapIndex == -1)
	{
		return 0;
	}
	MigrateMap map;
	g_Maps.GetArray(mapIndex, map);
	return map.newMapID;
}



// =====[ PRIVATE ]=====

static void AssignCourseIDs(MigrateMap map)
{
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
		course.newMapCourseID = g_NextMapCourseID;
		g_NextMapCourseID++;
		g_Courses.SetArray(courseIndex, course);
		Migrate_Detail("MapCourse %d (%s course %d) becomes MapCourse %d of MapID %d.", course.mapCourseID, map.targetName, course.course, course.newMapCourseID, map.newMapID);
	}
}

static void AssignMergedMapIDs()
{
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		if (map.status != MapStatus_Merged)
		{
			continue;
		}
		map.newMapID = GetNewMapID(map.targetMapID);
		g_Maps.SetArray(i, map);
	}
}

static void AssignMergedCourseIDs()
{
	for (int i = 0; i < g_Courses.Length; i++)
	{
		MigrateCourse course;
		g_Courses.GetArray(i, course);
		bool merged = course.targetMapCourseID != course.mapCourseID;
		if (!merged)
		{
			continue;
		}
		course.newMapCourseID = GetNewMapCourseID(course.targetMapCourseID);
		g_Courses.SetArray(i, course);
	}
}

static bool VerifyCourseIDs()
{
	for (int i = 0; i < g_Courses.Length; i++)
	{
		MigrateCourse course;
		g_Courses.GetArray(i, course);
		if (!course.keep || course.newMapCourseID != 0)
		{
			continue;
		}
		Migrate_Fail("MapCourse %d (MapID %d course %d) is kept but could not be given a new MapCourseID.", course.mapCourseID, course.mapID, course.course);
		return false;
	}
	return true;
}
