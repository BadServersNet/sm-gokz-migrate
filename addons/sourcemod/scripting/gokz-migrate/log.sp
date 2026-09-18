static File g_ReportMaps;
static File g_ReportPlayers;



// =====[ PUBLIC ]=====

void OpenLog()
{
	char directory[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directory, sizeof(directory), "logs/gokz-migrate");
	if (!DirExists(directory))
	{
		CreateDirectory(directory, 511);
	}

	char stamp[32];
	FormatTime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S");
	char kind[8];
	GetRunKind(kind, sizeof(kind));
	FormatEx(gC_ReportPrefix, sizeof(gC_ReportPrefix), "%s/%s_%s", directory, kind, stamp);
	FormatEx(gC_LogPath, sizeof(gC_LogPath), "%s.log", gC_ReportPrefix);
}

void Migrate_Log(const char[] format, any ...)
{
	char message[2048];
	VFormat(message, sizeof(message), format, 2);
	PrintToServer("[GOKZ Migrate] %s", message);
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

File Report_Maps()
{
	if (g_ReportMaps == null)
	{
		g_ReportMaps = OpenReport("maps", "MapID,Name,Status,TargetMapID,TargetName,TimesKept,Validated,Note");
	}
	return g_ReportMaps;
}

File Report_Players()
{
	if (g_ReportPlayers == null)
	{
		g_ReportPlayers = OpenReport("players_purged", "SteamID32,Alias,Cheater,LastPlayed,Created");
	}
	return g_ReportPlayers;
}

void CloseReports()
{
	delete g_ReportMaps;
	delete g_ReportPlayers;
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



// =====[ PRIVATE ]=====

static void GetRunKind(char[] buffer, int maxlength)
{
	if (gB_ListMapsOnly)
	{
		strcopy(buffer, maxlength, "maps");
		return;
	}
	if (gB_DryRun)
	{
		strcopy(buffer, maxlength, "dry");
		return;
	}
	strcopy(buffer, maxlength, "run");
}
