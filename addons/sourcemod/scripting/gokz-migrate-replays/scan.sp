#define MIGRATE_SCAN_DIRS_PER_TICK 25
#define MIGRATE_PARSE_FILES_PER_TICK 100

static int g_ScannedDirectories;
static int g_SkippedFiles;



// =====[ STEPS ]=====

bool Step_ScanDirectories()
{
	if (g_Cursor == 0)
	{
		g_Cursor = 1;
		g_ScannedDirectories = 0;
		g_SkippedFiles = 0;
		g_DirectoryQueue.PushString(gC_InputDirectory);
	}

	int handled = 0;
	while (g_DirectoryQueue.Length > 0 && handled < MIGRATE_SCAN_DIRS_PER_TICK)
	{
		char directory[PLATFORM_MAX_PATH];
		int last = g_DirectoryQueue.Length - 1;
		g_DirectoryQueue.GetString(last, directory, sizeof(directory));
		g_DirectoryQueue.Erase(last);
		ScanDirectory(directory);
		handled++;
	}

	if (g_DirectoryQueue.Length > 0)
	{
		return false;
	}
	Migrate_Log("Scanned %d directories under %s: %d replay files, %d other files skipped.", g_ScannedDirectories, gC_InputDirectory, g_FileQueue.Length, g_SkippedFiles);
	return true;
}

bool Step_ParseReplays()
{
	int end = IntMin(g_Cursor + MIGRATE_PARSE_FILES_PER_TICK, g_FileQueue.Length);
	for (int i = g_Cursor; i < end; i++)
	{
		char path[PLATFORM_MAX_PATH];
		g_FileQueue.GetString(i, path, sizeof(path));
		MigrateReplay replay;
		ParseReplayFile(path, replay);
		g_Replays.PushArray(replay);
	}
	g_Cursor = end;
	Migrate_Log("Parsed %d of %d replay files.", g_Cursor, g_FileQueue.Length);
	return g_Cursor >= g_FileQueue.Length;
}



// =====[ PUBLIC ]=====

void GetCategoryName(ReplayCategory category, char[] buffer, int maxlength)
{
	static const char names[][] = { "_runs", "_tempRuns", "_jumps", "_cheaters", "other" };
	strcopy(buffer, maxlength, names[view_as<int>(category)]);
}

void GetReplayTypeName(int replayType, char[] buffer, int maxlength)
{
	switch (replayType)
	{
		case ReplayType_Run: strcopy(buffer, maxlength, "run");
		case ReplayType_Jump: strcopy(buffer, maxlength, "jump");
		case ReplayType_Cheater: strcopy(buffer, maxlength, "cheater");
		default: FormatEx(buffer, maxlength, "type%d", replayType);
	}
}



// =====[ PRIVATE ]=====

static void ScanDirectory(const char[] directory)
{
	DirectoryListing listing = OpenDirectory(directory);
	if (listing == null)
	{
		Migrate_Log("WARNING: could not open directory %s", directory);
		return;
	}
	g_ScannedDirectories++;

	char name[PLATFORM_MAX_PATH];
	FileType type;
	while (listing.GetNext(name, sizeof(name), type))
	{
		if (StrEqual(name, ".") || StrEqual(name, ".."))
		{
			continue;
		}
		char path[PLATFORM_MAX_PATH];
		FormatEx(path, sizeof(path), "%s/%s", directory, name);
		if (type == FileType_Directory)
		{
			g_DirectoryQueue.PushString(path);
			continue;
		}
		if (type != FileType_File)
		{
			continue;
		}
		if (!HasReplayExtension(name))
		{
			g_SkippedFiles++;
			Migrate_Log("Skipping non-replay file %s", path);
			continue;
		}
		g_FileQueue.PushString(path);
	}
	delete listing;
}

static bool HasReplayExtension(const char[] name)
{
	char suffix[16];
	FormatEx(suffix, sizeof(suffix), ".%s", RP_FILE_EXTENSION);
	int nameLength = strlen(name);
	int suffixLength = strlen(suffix);
	if (nameLength <= suffixLength)
	{
		return false;
	}
	return StrEqual(name[nameLength - suffixLength], suffix, false);
}

static ReplayCategory CategoryFromPath(const char[] path)
{
	int rootLength = strlen(gC_InputDirectory);
	char relative[PLATFORM_MAX_PATH];
	strcopy(relative, sizeof(relative), path[rootLength + 1]);
	int slash = FindCharInString(relative, '/');
	if (slash != -1)
	{
		relative[slash] = '\0';
	}
	if (StrEqual(relative, "_runs", false))
	{
		return ReplayCategory_Runs;
	}
	if (StrEqual(relative, "_tempRuns", false))
	{
		return ReplayCategory_TempRuns;
	}
	if (StrEqual(relative, "_jumps", false))
	{
		return ReplayCategory_Jumps;
	}
	if (StrEqual(relative, "_cheaters", false))
	{
		return ReplayCategory_Cheaters;
	}
	return ReplayCategory_Other;
}

static void ParseReplayFile(const char[] path, MigrateReplay replay)
{
	strcopy(replay.path, sizeof(MigrateReplay::path), path);
	replay.category = CategoryFromPath(path);
	replay.fileSize = FileSize(path);
	replay.recordIndex = -1;
	replay.status = MatchStatus_Unreadable;

	File file = OpenFile(path, "rb");
	if (file == null)
	{
		strcopy(replay.note, sizeof(MigrateReplay::note), "could not open file");
		Migrate_Log("Unreadable replay %s: could not open file.", path);
		return;
	}

	int magicNumber;
	file.ReadInt32(magicNumber);
	if (magicNumber != RP_MAGIC_NUMBER)
	{
		delete file;
		strcopy(replay.note, sizeof(MigrateReplay::note), "bad magic number");
		Migrate_Log("Unreadable replay %s: bad magic number 0x%X.", path, magicNumber);
		return;
	}

	file.ReadInt8(replay.formatVersion);
	switch (replay.formatVersion)
	{
		case 1: ParseVersion1Header(file, replay);
		case 2: ParseVersion2Header(file, replay);
		default:
		{
			FormatEx(replay.note, sizeof(MigrateReplay::note), "unsupported format version %d", replay.formatVersion);
			Migrate_Log("Unreadable replay %s: unsupported format version %d.", path, replay.formatVersion);
		}
	}
	delete file;
}

static void ParseVersion1Header(File file, MigrateReplay replay)
{
	replay.replayType = ReplayType_Run;
	SkipString(file);
	ReadString(file, replay.map, sizeof(MigrateReplay::map));
	file.ReadInt32(replay.course);
	file.ReadInt32(replay.mode);
	file.ReadInt32(replay.style);
	int timeBits;
	file.ReadInt32(timeBits);
	replay.time = view_as<float>(timeBits);
	file.ReadInt32(replay.teleports);
	file.ReadInt32(replay.steamID);
	SkipString(file);
	SkipString(file);
	SkipString(file);
	file.ReadInt32(replay.tickCount);
	replay.timestamp = GetFileTime(replay.path, FileTime_LastChange);
	replay.status = MatchStatus_Unmatched;
	strcopy(replay.note, sizeof(MigrateReplay::note), "format v1, timestamp taken from file modification time");
}

static void ParseVersion2Header(File file, MigrateReplay replay)
{
	file.ReadInt8(replay.replayType);
	SkipString(file);
	ReadString(file, replay.map, sizeof(MigrateReplay::map));
	file.Seek(8, SEEK_CUR);
	file.ReadInt32(replay.timestamp);
	SkipString(file);
	file.ReadInt32(replay.steamID);
	file.ReadInt8(replay.mode);
	file.ReadInt8(replay.style);
	file.Seek(12, SEEK_CUR);
	file.ReadInt32(replay.tickCount);
	file.Seek(8, SEEK_CUR);

	switch (replay.replayType)
	{
		case ReplayType_Run:
		{
			int timeBits;
			file.ReadInt32(timeBits);
			replay.time = view_as<float>(timeBits);
			file.ReadInt8(replay.course);
			file.ReadInt32(replay.teleports);
			replay.status = MatchStatus_Unmatched;
		}
		case ReplayType_Jump:
		{
			file.ReadInt8(replay.jumpType);
			int distanceBits;
			file.ReadInt32(distanceBits);
			replay.distance = view_as<float>(distanceBits);
			file.ReadInt32(replay.block);
			file.ReadInt8(replay.strafes);
			replay.status = MatchStatus_Unmatched;
		}
		case ReplayType_Cheater:
		{
			replay.status = MatchStatus_Cheater;
		}
		default:
		{
			replay.status = MatchStatus_UnsupportedType;
			FormatEx(replay.note, sizeof(MigrateReplay::note), "unknown replay type %d", replay.replayType);
			Migrate_Log("Replay %s has unknown replay type %d.", replay.path, replay.replayType);
		}
	}
}

static void SkipString(File file)
{
	int length;
	file.ReadInt8(length);
	length &= 0xFF;
	file.Seek(length, SEEK_CUR);
}

static void ReadString(File file, char[] buffer, int maxlength)
{
	int length;
	file.ReadInt8(length);
	length &= 0xFF;
	if (length >= maxlength)
	{
		file.Seek(length, SEEK_CUR);
		buffer[0] = '\0';
		return;
	}
	file.ReadString(buffer, maxlength, length);
	buffer[length] = '\0';
}
