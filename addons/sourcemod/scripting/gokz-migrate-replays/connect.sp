// =====[ STEP ]=====

bool Step_Connect()
{
	if (!ConnectInput())
	{
		return false;
	}
	if (!ConnectOutput())
	{
		return false;
	}
	if (!VerifyDistinctDatabases())
	{
		return false;
	}
	if (!VerifyReplayPlugin())
	{
		return false;
	}
	if (!DirExists(gC_InputDirectory))
	{
		Migrate_Fail("Input directory \"%s\" does not exist.", gC_InputDirectory);
		return false;
	}
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
	Migrate_Log("Input database: %s, migrated database: %s", inputName, outputName);
	if (StrEqual(inputName, outputName))
	{
		Migrate_Fail("Input and migrated database are the same database (%s). Refusing to continue.", inputName);
		return false;
	}

	int outputTimes = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM Times");
	if (outputTimes < 0)
	{
		return false;
	}
	int outputJumps = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM Jumpstats");
	if (outputJumps < 0)
	{
		return false;
	}
	int outputReplays = Migrate_FetchScalarInt(gH_OutputDB, "SELECT COUNT(*) FROM Replays");
	if (outputReplays < 0)
	{
		return false;
	}
	Migrate_Log("Migrated database currently holds %d times, %d jumps and %d replay rows.", outputTimes, outputJumps, outputReplays);
	if (outputTimes == 0 && outputJumps == 0)
	{
		Migrate_Log("WARNING: the migrated database has no times or jumps. Run the gokz-migrate SQL migration first, otherwise no replay can be imported.");
	}
	return true;
}

static bool VerifyReplayPlugin()
{
	if (!LibraryExists("gokz-replays"))
	{
		Migrate_Fail("gokz-replays is not loaded; it is needed to import replays into the store.");
		return false;
	}
	int pending = GOKZ_RP_GetPendingUploadCount();
	Migrate_Log("gokz-replays currently has %d pending uploads.", pending);
	if (gB_DryRun || pending == 0)
	{
		return true;
	}
	int dropped = GOKZ_RP_ClearUploadQueue();
	Migrate_Log("Dropped %d pending uploads and their outbox markers; every matched replay is queued again by this run.", dropped);
	return true;
}
