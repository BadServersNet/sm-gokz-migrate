// =====[ STEP ]=====

bool Step_Connect()
{
	if (!ConnectInput())
	{
		return false;
	}
	if (gB_ListMapsOnly)
	{
		LoadRenames();
		return true;
	}
	if (!ConnectOutput())
	{
		return false;
	}
	if (!VerifyDistinctDatabases())
	{
		return false;
	}
	LoadRenames();
	return true;
}



// =====[ PRIVATE ]=====

static bool ConnectInput()
{
	char error[256];
	gH_InputDB = SQL_Connect("gokz-input", true, error, sizeof(error));
	if (gH_InputDB == null)
	{
		Migrate_Fail("Could not connect to the \"gokz-input\" database: %s", error);
		return false;
	}

	char driver[16];
	SQL_ReadDriver(gH_InputDB, driver, sizeof(driver));
	if (!StrEqual(driver, "mysql", false))
	{
		Migrate_Fail("The \"gokz-input\" database must use the mysql driver, found \"%s\".", driver);
		return false;
	}
	Migrate_Log("Connected to the gokz-input database.");
	return true;
}

static bool ConnectOutput()
{
	gH_OutputDB = GOKZ_DB_GetDatabase();
	if (gH_OutputDB == null)
	{
		Migrate_Fail("gokz-localdb is not connected to the \"gokz\" database.");
		return false;
	}
	if (GOKZ_DB_GetDatabaseType() != DatabaseType_MySQL)
	{
		Migrate_Fail("The \"gokz\" database must be MySQL.");
		return false;
	}
	Migrate_Log("Connected to the gokz database through gokz-localdb.");
	return true;
}

static bool VerifyDistinctDatabases()
{
	char inputName[128];
	char outputName[128];
	if (!Migrate_FetchScalarString(gH_InputDB, "SELECT DATABASE()", inputName, sizeof(inputName)))
	{
		return false;
	}
	if (!Migrate_FetchScalarString(gH_OutputDB, "SELECT DATABASE()", outputName, sizeof(outputName)))
	{
		return false;
	}
	Migrate_Log("Input database: %s, output database: %s", inputName, outputName);
	if (StrEqual(inputName, outputName))
	{
		Migrate_Fail("Input and output are the same database (%s). Refusing to continue.", inputName);
		return false;
	}

	int outputTimes = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM Times");
	if (outputTimes < 0)
	{
		return false;
	}
	int outputPlayers = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM Players");
	if (outputPlayers < 0)
	{
		return false;
	}
	int outputReplays = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM Replays");
	if (outputReplays < 0)
	{
		return false;
	}
	Migrate_Log("Output database currently holds %d players, %d times and %d replay rows.", outputPlayers, outputTimes, outputReplays);

	int rankedPool = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='Maps' AND COLUMN_NAME='InRankedPool'");
	if (rankedPool < 0)
	{
		return false;
	}
	gB_OutputHasRankedPool = rankedPool > 0;
	Migrate_Log("Output Maps table %s the InRankedPool column.", gB_OutputHasRankedPool ? "has" : "does not have");
	return true;
}

static void LoadRenames()
{
	char path[PLATFORM_MAX_PATH];
	gCV_gokz_migrate_renames_file.GetString(path, sizeof(path));
	if (path[0] == '\0' || !FileExists(path))
	{
		Migrate_Log("No map rename file found at \"%s\".", path);
		return;
	}

	KeyValues kv = new KeyValues("Renames");
	if (!kv.ImportFromFile(path))
	{
		Migrate_Log("WARNING: could not parse rename file \"%s\".", path);
		delete kv;
		return;
	}
	if (!kv.GotoFirstSubKey(false))
	{
		Migrate_Log("Rename file \"%s\" is empty.", path);
		delete kv;
		return;
	}

	do
	{
		char oldName[64];
		char newName[64];
		kv.GetSectionName(oldName, sizeof(oldName));
		kv.GetString(NULL_STRING, newName, sizeof(newName));
		String_ToLower(oldName, oldName, sizeof(oldName));
		String_ToLower(newName, newName, sizeof(newName));
		if (oldName[0] == '\0' || newName[0] == '\0')
		{
			continue;
		}
		g_Renames.SetString(oldName, newName);
		Migrate_Log("Rename rule: %s -> %s", oldName, newName);
	}
	while (kv.GotoNextKey(false));
	delete kv;
	Migrate_Log("Loaded %d map rename rules from \"%s\".", g_Renames.Size, path);
}
