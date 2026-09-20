#define MIGRATE_GLOBAL_PAGE_SIZE 500
#define MIGRATE_GLOBAL_TIMEOUT 60
#define MIGRATE_GLOBAL_MIN_MAPS 100

enum GlobalRequestState
{
	GlobalRequest_NotStarted = 0,
	GlobalRequest_InFlight,
	GlobalRequest_PageDone,
	GlobalRequest_Finished,
	GlobalRequest_Failed
};

static GlobalRequestState g_GlobalState;
static int g_GlobalOffset;
static int g_GlobalRequestTime;
static Regex g_StemRegex;



// =====[ STEP ]=====

bool Step_FetchGlobalMaps()
{
	if (g_Cursor == 0)
	{
		g_Cursor = 1;
		g_GlobalState = GlobalRequest_NotStarted;
		g_GlobalOffset = 0;
		if (LoadGlobalMapsFromFile())
		{
			return true;
		}
	}

	switch (g_GlobalState)
	{
		case GlobalRequest_NotStarted, GlobalRequest_PageDone:
		{
			RequestGlobalMapsPage();
			return false;
		}
		case GlobalRequest_InFlight:
		{
			if (GetTime() - g_GlobalRequestTime > MIGRATE_GLOBAL_TIMEOUT)
			{
				Migrate_Fail("The Global API did not answer the map list request within %d seconds.", MIGRATE_GLOBAL_TIMEOUT);
			}
			return false;
		}
		case GlobalRequest_Failed:
		{
			Migrate_Fail("Could not fetch the global map list. Nothing will be deleted without it.");
			return false;
		}
	}

	if (g_GlobalMaps.Size < MIGRATE_GLOBAL_MIN_MAPS)
	{
		Migrate_Fail("The global map list only has %d maps, which looks incomplete. Nothing will be deleted based on it.", g_GlobalMaps.Size);
		return false;
	}
	Migrate_Log("Global map list has %d maps.", g_GlobalMaps.Size);
	return true;
}



// =====[ PUBLIC ]=====

bool IsGlobalMap(const char[] name, bool &validated)
{
	char lower[64];
	String_ToLower(name, lower, sizeof(lower));
	int value;
	if (!g_GlobalMaps.GetValue(lower, value))
	{
		return false;
	}
	validated = value != 0;
	return true;
}

void GetMapStem(const char[] name, char[] buffer, int maxlength)
{
	if (g_StemRegex == null)
	{
		g_StemRegex = new Regex("(_v\\d+[a-z0-9]*|_final[a-z0-9]*|_fix[a-z0-9]*|_b\\d+[a-z]?|_beta[a-z0-9]*|_rc\\d*|_go|_csgo|_ez|_hard|_easy|_remake|_new|_edit|_x|_zp|_gfix|\\d+)$");
	}

	String_ToLower(name, buffer, maxlength);
	int guard = 0;
	while (guard < 6)
	{
		guard++;
		int matchStart = FindStemSuffix(buffer);
		if (matchStart <= 4)
		{
			break;
		}
		buffer[matchStart] = '\0';
	}
}

void FindRenameCandidates(const char[] name, char[] buffer, int maxlength)
{
	buffer[0] = '\0';
	char stem[64];
	GetMapStem(name, stem, sizeof(stem));

	ArrayList sameStem = ListMapGet(g_GlobalStems, stem);
	if (sameStem != null)
	{
		AppendGlobalCandidates(sameStem, name, buffer, maxlength);
	}

	char needle[64];
	StripMapPrefix(stem, needle, sizeof(needle));
	if (strlen(needle) < 5)
	{
		return;
	}

	StringMapSnapshot snapshot = g_GlobalMaps.Snapshot();
	for (int i = 0; i < snapshot.Length; i++)
	{
		char globalName[64];
		snapshot.GetKey(i, globalName, sizeof(globalName));
		if (StrEqual(globalName, name, false) || StrContains(buffer, globalName) != -1)
		{
			continue;
		}
		char globalNeedle[64];
		StripMapPrefix(globalName, globalNeedle, sizeof(globalNeedle));
		bool related = StrContains(globalName, needle) != -1 || (strlen(globalNeedle) >= 5 && StrContains(stem, globalNeedle) != -1);
		if (!related)
		{
			continue;
		}
		AppendCandidate(globalName, buffer, maxlength);
	}
	delete snapshot;
}



// =====[ CALLBACKS ]=====

public int GetGlobalMapsCallback(JSON_Object maps, GlobalAPIRequestData request, any offset)
{
	if (g_Step != MigrateStep_FetchGlobalMaps)
	{
		return 0;
	}
	if (request.Failure || maps == null)
	{
		Migrate_Log("Global API map request at offset %d failed.", offset);
		g_GlobalState = GlobalRequest_Failed;
		return 0;
	}
	if (!maps.IsArray)
	{
		Migrate_Log("Global API returned a malformed map list at offset %d.", offset);
		g_GlobalState = GlobalRequest_Failed;
		return 0;
	}

	int count = maps.Length;
	for (int i = 0; i < count; i++)
	{
		APIMap map = view_as<APIMap>(maps.GetObjectIndexed(i));
		char name[64];
		map.GetName(name, sizeof(name));
		AddGlobalMap(name, map.IsValidated);
	}
	Migrate_Log("Global API map page at offset %d returned %d maps (%d total so far).", offset, count, g_GlobalMaps.Size);

	g_GlobalOffset = offset + count;
	g_GlobalState = count == 0 ? GlobalRequest_Finished : GlobalRequest_PageDone;
	return 0;
}



// =====[ PRIVATE ]=====

static void RequestGlobalMapsPage()
{
	if (!LibraryExists("GlobalAPI"))
	{
		Migrate_Log("The GlobalAPI plugin is not loaded and no global map file was found; set gokz_migrate_global_maps_file.");
		g_GlobalState = GlobalRequest_Failed;
		return;
	}
	g_GlobalState = GlobalRequest_InFlight;
	g_GlobalRequestTime = GetTime();
	Migrate_Log("Requesting global maps from offset %d.", g_GlobalOffset);
	bool sent = GlobalAPI_GetMaps(GetGlobalMapsCallback, g_GlobalOffset, DEFAULT_STRING, DEFAULT_INT, DEFAULT_INT, true, DEFAULT_INT, DEFAULT_STRING, DEFAULT_STRING, g_GlobalOffset, MIGRATE_GLOBAL_PAGE_SIZE);
	if (!sent)
	{
		Migrate_Log("GlobalAPI_GetMaps refused to send the request.");
		g_GlobalState = GlobalRequest_Failed;
	}
}

static bool LoadGlobalMapsFromFile()
{
	char path[PLATFORM_MAX_PATH];
	gCV_gokz_migrate_global_maps_file.GetString(path, sizeof(path));
	if (path[0] == '\0')
	{
		return false;
	}
	File file = OpenFile(path, "r");
	if (file == null)
	{
		Migrate_Log("Global map file \"%s\" not found, falling back to the Global API.", path);
		return false;
	}

	char line[128];
	while (file.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] == '\0' || line[0] == ';' || line[0] == '/')
		{
			continue;
		}
		AddGlobalMap(line, true);
	}
	delete file;
	Migrate_Log("Loaded %d global maps from \"%s\" instead of the Global API.", g_GlobalMaps.Size, path);
	return true;
}

static void AddGlobalMap(const char[] name, bool validated)
{
	char lower[64];
	String_ToLower(name, lower, sizeof(lower));
	if (lower[0] == '\0')
	{
		return;
	}
	g_GlobalMaps.SetValue(lower, validated ? 1 : 0);

	char stem[64];
	GetMapStem(lower, stem, sizeof(stem));
	ArrayList names = ListMapGet(g_GlobalStems, stem);
	if (names == null)
	{
		names = new ArrayList(ByteCountToCells(64));
		g_GlobalStems.SetValue(stem, names);
	}
	if (names.FindString(lower) == -1)
	{
		names.PushString(lower);
	}
}

static int FindStemSuffix(const char[] name)
{
	if (g_StemRegex.Match(name) <= 0)
	{
		return -1;
	}
	char suffix[64];
	g_StemRegex.GetSubString(0, suffix, sizeof(suffix));
	return strlen(name) - strlen(suffix);
}

static void StripMapPrefix(const char[] name, char[] buffer, int maxlength)
{
	static const char prefixes[][] = { "kz_", "bkz_", "xc_", "kzpro_", "skz_", "vnl_", "kzt_" };
	strcopy(buffer, maxlength, name);
	for (int i = 0; i < sizeof(prefixes); i++)
	{
		if (StrContains(buffer, prefixes[i]) == 0)
		{
			strcopy(buffer, maxlength, buffer[strlen(prefixes[i])]);
			return;
		}
	}
}

static void AppendGlobalCandidates(ArrayList names, const char[] self, char[] buffer, int maxlength)
{
	for (int i = 0; i < names.Length; i++)
	{
		char name[64];
		names.GetString(i, name, sizeof(name));
		if (StrEqual(name, self, false))
		{
			continue;
		}
		AppendCandidate(name, buffer, maxlength);
	}
}

static void AppendCandidate(const char[] name, char[] buffer, int maxlength)
{
	if (buffer[0] != '\0')
	{
		StrCat(buffer, maxlength, " ");
	}
	StrCat(buffer, maxlength, name);
}
