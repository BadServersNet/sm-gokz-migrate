static File g_ReportTimes;
static File g_ReportJumps;
static File g_ReportReplays;



// =====[ PUBLIC ]=====

void OpenLog()
{
	gCV_gokz_migrate_replays_input_dir.GetString(gC_InputDirectory, sizeof(gC_InputDirectory));
	char inputPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, inputPath, sizeof(inputPath), "%s", gC_InputDirectory);
	strcopy(gC_InputDirectory, sizeof(gC_InputDirectory), inputPath);

	char directory[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directory, sizeof(directory), "logs/gokz-migrate-replays");
	if (!DirExists(directory))
	{
		CreateDirectory(directory, 511);
	}

	char stamp[32];
	FormatTime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S");
	FormatEx(gC_ReportPrefix, sizeof(gC_ReportPrefix), "%s/%s_%s", directory, gB_DryRun ? "dry" : "run", stamp);
	FormatEx(gC_LogPath, sizeof(gC_LogPath), "%s.log", gC_ReportPrefix);
}

void Migrate_Log(const char[] format, any ...)
{
	char message[2048];
	VFormat(message, sizeof(message), format, 2);
	PrintToServer("[GOKZ Migrate Replays] %s", message);
	if (gC_LogPath[0] == '\0')
	{
		return;
	}
	LogToFileEx(gC_LogPath, "%s", message);
}

File OpenReport(const char[] suffix, const char[] header)
{
	char path[PLATFORM_MAX_PATH];
	FormatEx(path, sizeof(path), "%s_%s.csv", gC_ReportPrefix, suffix);
	File file = OpenFile(path, "w");
	if (file == null)
	{
		Migrate_Log("WARNING: could not create report \"%s\".", path);
		return null;
	}
	file.WriteLine("%s", header);
	Migrate_Log("Writing report %s", path);
	return file;
}

void ReportLine(File file, const char[] format, any ...)
{
	if (file == null)
	{
		return;
	}
	char line[2048];
	VFormat(line, sizeof(line), format, 3);
	file.WriteLine("%s", line);
}

File Report_Times()
{
	if (g_ReportTimes == null)
	{
		g_ReportTimes = OpenReport("times_without_replay", "TimeID,SteamID32,Map,Course,Mode,Style,RunTimeMS,Teleports,Created,Migrated");
	}
	return g_ReportTimes;
}

File Report_Jumps()
{
	if (g_ReportJumps == null)
	{
		g_ReportJumps = OpenReport("jumps_without_replay", "JumpID,SteamID32,JumpType,Mode,Distance,IsBlockJump,Block,Created,Migrated");
	}
	return g_ReportJumps;
}

File Report_Replays()
{
	if (g_ReportReplays == null)
	{
		g_ReportReplays = OpenReport("replays", "Path,Category,Format,Type,Map,SteamID32,Mode,Style,Timestamp,Course,Time,Teleports,JumpType,Distance,Block,Ticks,Bytes,Status,RecordID,TargetMap,Key,Imported,Note");
	}
	return g_ReportReplays;
}

void CloseReports()
{
	delete g_ReportTimes;
	delete g_ReportJumps;
	delete g_ReportReplays;
}

void CsvEscape(const char[] input, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, input);
	ReplaceString(buffer, maxlength, "\"", "\"\"");
	Format(buffer, maxlength, "\"%s\"", buffer);
}

void FormatUnixTime(int timestamp, char[] buffer, int maxlength)
{
	if (timestamp <= 0)
	{
		strcopy(buffer, maxlength, "");
		return;
	}
	FormatTime(buffer, maxlength, "%Y-%m-%d %H:%M:%S", timestamp);
}
