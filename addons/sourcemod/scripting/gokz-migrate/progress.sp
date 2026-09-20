#define MIGRATE_PROGRESS_INTERVAL 5

static int g_LastProgressTime;



// =====[ PUBLIC ]=====

void Progress_Print()
{
	int now = GetTime();
	if (now - g_LastProgressTime < MIGRATE_PROGRESS_INTERVAL)
	{
		return;
	}
	g_LastProgressTime = now;

	char stepName[64];
	GetStepName(g_Step, stepName, sizeof(stepName));
	int stepNumber = view_as<int>(g_Step);
	int stepCount = view_as<int>(MigrateStep_Summary);
	char elapsed[32];
	FormatDuration(now - g_StartTime, elapsed, sizeof(elapsed));
	char stepProgress[128];
	FormatStepProgress(now, stepProgress, sizeof(stepProgress));
	PrintToServer("[GOKZ Migrate] >>>>>>>>>> PROGRESS step %d/%d %s | %s | elapsed %s <<<<<<<<<<", stepNumber, stepCount, stepName, stepProgress, elapsed);
}



// =====[ PRIVATE ]=====

static void FormatStepProgress(int now, char[] buffer, int maxlength)
{
	int total = GetStepTotal(g_Step);
	if (total <= 0)
	{
		strcopy(buffer, maxlength, "running");
		return;
	}

	int done = IntMin(g_Cursor, total);
	float fraction = float(done) / float(total);
	int stepElapsed = now - g_StepStartTime;
	if (done == 0 || stepElapsed == 0)
	{
		FormatEx(buffer, maxlength, "%.1f%% (%d/%d) | step ETA unknown", fraction * 100.0, done, total);
		return;
	}

	float remainingFraction = float(total - done) / float(done);
	int remaining = RoundToCeil(float(stepElapsed) * remainingFraction);
	char eta[32];
	FormatDuration(remaining, eta, sizeof(eta));
	FormatEx(buffer, maxlength, "%.1f%% (%d/%d) | step ETA %s", fraction * 100.0, done, total, eta);
}

static int GetStepTotal(MigrateStep step)
{
	switch (step)
	{
		case MigrateStep_AnalyzeTimes, MigrateStep_AssignTimeIDs, MigrateStep_InsertTimes, MigrateStep_ReportTimes: return g_Times.Length;
		case MigrateStep_ParseReplays: return g_FileQueue.Length;
		case MigrateStep_MatchReplays, MigrateStep_ImportReplays, MigrateStep_ReportReplays: return g_Replays.Length;
		case MigrateStep_InsertPlayers: return g_Players.Length;
		case MigrateStep_InsertMaps: return g_Maps.Length;
	}
	return 0;
}

static void FormatDuration(int seconds, char[] buffer, int maxlength)
{
	int hours = seconds / 3600;
	int minutes = (seconds % 3600) / 60;
	int rest = seconds % 60;
	if (hours > 0)
	{
		FormatEx(buffer, maxlength, "%dh %02dm %02ds", hours, minutes, rest);
		return;
	}
	FormatEx(buffer, maxlength, "%dm %02ds", minutes, rest);
}
