#define MIGRATE_IMPORTS_PER_TICK 5

static int g_ImportedCount;
static int g_ImportFailedCount;
static int g_ImportSkippedCount;



// =====[ STEP ]=====

bool Step_ImportReplays()
{
	if (g_Cursor == 0)
	{
		g_ImportedCount = 0;
		g_ImportFailedCount = 0;
		g_ImportSkippedCount = 0;
	}

	int end = IntMin(g_Cursor + MIGRATE_IMPORTS_PER_TICK, g_Replays.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		MigrateReplay replay;
		g_Replays.GetArray(i, replay);
		ImportReplay(replay);
		g_Replays.SetArray(i, replay);
	}
	g_Cursor = end;

	bool finished = g_Cursor >= g_Replays.Length;
	if (finished || g_Cursor % 100 == 0)
	{
		Migrate_Detail("Import progress: %d of %d replays handled, %d imported, %d failed, %d skipped, %d uploads pending in gokz-replays.", g_Cursor, g_Replays.Length, g_ImportedCount, g_ImportFailedCount, g_ImportSkippedCount, GOKZ_RP_GetPendingUploadCount());
	}
	return finished;
}



// =====[ PRIVATE ]=====

static void ImportReplay(MigrateReplay replay)
{
	if (replay.status != MatchStatus_Matched)
	{
		g_ImportSkippedCount++;
		return;
	}

	replay.imported = GOKZ_RP_ImportReplay(replay.path, replay.replayType, replay.recordID, replay.steamID, replay.targetMap, replay.timestamp, replay.mode, replay.style, replay.key, sizeof(MigrateReplay::key));
	if (!replay.imported)
	{
		g_ImportFailedCount++;
		StrCat(replay.note, sizeof(MigrateReplay::note), " import failed");
		Migrate_Log("Import of %s failed (see the gokz-replays error log).", replay.path);
		return;
	}
	g_ImportedCount++;
	Migrate_Detail("Queued %s as %s (record %d, %d bytes).", replay.path, replay.key, replay.recordID, replay.fileSize);
}
