#include <sourcemod>
#include <regex>

#include <gokz/core>
#include <gokz/localdb>
#include <gokz/replays>

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#include <GlobalAPI>
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 1048576

#define PLUGIN_VERSION "0.1.0"



public Plugin myinfo =
{
	name = "GOKZ Migrate",
	author = "BuSheey",
	description = "One-time migration of a legacy gokz database and replay folder into a rebuilt gokz database",
	version = PLUGIN_VERSION,
	url = GOKZ_SOURCE_URL
};

enum MigrateStep
{
	MigrateStep_Idle = 0,
	MigrateStep_Connect,
	MigrateStep_FetchGlobalMaps,
	MigrateStep_LoadMaps,
	MigrateStep_LoadCourses,
	MigrateStep_LoadPlayers,
	MigrateStep_LoadTimes,
	MigrateStep_LoadPositions,
	MigrateStep_AnalyzeMaps,
	MigrateStep_AnalyzeCourses,
	MigrateStep_AnalyzeTimes,
	MigrateStep_AnalyzePlayers,
	MigrateStep_AnalyzeHanging,
	MigrateStep_AssignMapIDs,
	MigrateStep_AssignTimeIDs,
	MigrateStep_ScanDirectories,
	MigrateStep_ParseReplays,
	MigrateStep_MatchReplays,
	MigrateStep_WipeOutput,
	MigrateStep_InsertPlayers,
	MigrateStep_InsertMaps,
	MigrateStep_InsertTimes,
	MigrateStep_InsertPositions,
	MigrateStep_ImportReplays,
	MigrateStep_ReportMaps,
	MigrateStep_ReportPlayers,
	MigrateStep_ReportTimes,
	MigrateStep_ReportReplays,
	MigrateStep_Summary,
	MigrateStep_ListMaps,
	MigrateStep_Done
};

enum MapStatus
{
	MapStatus_Global = 0,
	MapStatus_Renamed,
	MapStatus_Merged,
	MapStatus_Deleted,
	MapStatus_Hanging
};

enum ReplayCategory
{
	ReplayCategory_Runs = 0,
	ReplayCategory_TempRuns,
	ReplayCategory_Other
};

enum MatchStatus
{
	MatchStatus_Unmatched = 0,
	MatchStatus_Matched,
	MatchStatus_Duplicate,
	MatchStatus_RecordMissing,
	MatchStatus_MapUnknown,
	MatchStatus_CourseUnknown,
	MatchStatus_PlayerUnknown,
	MatchStatus_Unreadable,
	MatchStatus_UnsupportedType
};

enum struct MigrateMap
{
	int mapID;
	char name[64];
	int lastPlayed;
	int created;
	int inRankedPool;
	MapStatus status;
	int targetMapID;
	int newMapID;
	char targetName[64];
	int timeCount;
	bool validated;
	char note[256];
}

enum struct MigrateCourse
{
	int mapCourseID;
	int mapID;
	int course;
	int created;
	bool keep;
	int targetMapID;
	int targetMapCourseID;
	int newMapCourseID;
	int timeCount;
}

enum struct MigratePlayer
{
	int steamID;
	char alias[MAX_NAME_LENGTH];
	char country[192];
	char ip[16];
	bool aliasNull;
	bool countryNull;
	bool ipNull;
	int cheater;
	int lastPlayed;
	int created;
	bool keep;
	int timeCount;
}

enum struct MigrateTime
{
	int timeID;
	int steamID;
	int mapCourseID;
	int mode;
	int style;
	int runTime;
	int teleports;
	int created;
	bool keep;
	int targetMapCourseID;
	int newTimeID;
	int replayIndex;
	int nextIndex;
}

enum struct MigrateVBPosition
{
	int steamID;
	int mapID;
	float x;
	float y;
	float z;
	int course;
	int isStart;
	bool keep;
	int targetMapID;
}

enum struct MigrateStartPosition
{
	int steamID;
	int mapID;
	float x;
	float y;
	float z;
	float angle0;
	float angle1;
	bool keep;
	int targetMapID;
}

enum struct MigrateReplay
{
	char path[PLATFORM_MAX_PATH];
	ReplayCategory category;
	int fileSize;
	int formatVersion;
	int replayType;
	char map[64];
	int steamID;
	int mode;
	int style;
	int timestamp;
	int tickCount;
	int course;
	float time;
	int teleports;
	MatchStatus status;
	int legacyTimeID;
	int recordID;
	int recordIndex;
	char targetMap[64];
	char key[RP_MAX_KEY_LENGTH];
	bool imported;
	char note[192];
}

Database gH_InputDB;
Database gH_OutputDB;
bool gB_DryRun;
bool gB_ListMapsOnly;
int g_ListUserID;
MigrateStep g_Step;
Handle g_StepTimer;
int g_StartTime;
int g_StepStartTime;
int g_Cursor;
int g_LastID;
int g_BatchNumber;
bool g_InStepTimer;
bool g_HibernateWasEnabled;

ArrayList g_Maps;
ArrayList g_Courses;
ArrayList g_Players;
ArrayList g_Times;
ArrayList g_VBPositions;
ArrayList g_StartPositions;
ArrayList g_Replays;
ArrayList g_DirectoryQueue;
ArrayList g_FileQueue;

StringMap g_MapIndexByName;
StringMap g_MapIndexByID;
StringMap g_CourseIndexByKey;
StringMap g_CourseIndexByID;
StringMap g_PlayerIndexByID;
StringMap g_TimeIndexesByKey;
StringMap g_GlobalMaps;
StringMap g_GlobalStems;
StringMap g_Renames;

char gC_InputDirectory[PLATFORM_MAX_PATH];
char gC_LogPath[PLATFORM_MAX_PATH];
char gC_ReportPrefix[PLATFORM_MAX_PATH];
bool gB_InputHasRankedPool;
bool gB_OutputHasRankedPool;

ConVar gCV_gokz_migrate_global_maps_file;
ConVar gCV_gokz_migrate_renames_file;
ConVar gCV_gokz_migrate_keep_cheater_players;
ConVar gCV_gokz_migrate_replays_input_dir;

#include "gokz-migrate/log.sp"
#include "gokz-migrate/sql.sp"
#include "gokz-migrate/progress.sp"
#include "gokz-migrate/connect.sp"
#include "gokz-migrate/global_maps.sp"
#include "gokz-migrate/load.sp"
#include "gokz-migrate/analyze.sp"
#include "gokz-migrate/assign.sp"
#include "gokz-migrate/scan.sp"
#include "gokz-migrate/match.sp"
#include "gokz-migrate/output.sp"
#include "gokz-migrate/import.sp"
#include "gokz-migrate/report.sp"
#include "gokz-migrate/list_maps.sp"



// =====[ PLUGIN EVENTS ]=====

public void OnPluginStart()
{
	gCV_gokz_migrate_global_maps_file = CreateConVar("gokz_migrate_global_maps_file", "cfg/sourcemod/gokz/gokz-migrate-global-maps.txt", "File with one global map name per line. Used when it exists or when the GlobalAPI plugin is not loaded.");
	gCV_gokz_migrate_renames_file = CreateConVar("gokz_migrate_renames_file", "cfg/sourcemod/gokz/gokz-migrate-renames.cfg", "KeyValues file mapping old map names to their current global names.");
	gCV_gokz_migrate_keep_cheater_players = CreateConVar("gokz_migrate_keep_cheater_players", "1", "Whether players flagged as cheaters are kept even when they have no times.", _, true, 0.0, true, 1.0);

	gCV_gokz_migrate_replays_input_dir = CreateConVar("gokz_migrate_replays_input_dir", "data/gokz-replays/input", "Legacy replay folder to migrate, relative to addons/sourcemod. It is never modified.");

	RegAdminCmd("sm_gokz_migrate_dry", CommandMigrateDry, ADMFLAG_ROOT, "[KZ] Analyze the legacy database and replay folder without changing anything.");
	RegAdminCmd("sm_gokz_migrate_run", CommandMigrateRun, ADMFLAG_ROOT, "[KZ] Wipe the gokz database, migrate the legacy data into it and import the legacy replays.");
	RegAdminCmd("sm_gokz_migrate_nonglobal_maps", CommandMigrateNonGlobalMaps, ADMFLAG_ROOT, "[KZ] List the maps in the legacy database that are not on the Global API map list.");
	RegAdminCmd("sm_gokz_migrate_status", CommandMigrateStatus, ADMFLAG_ROOT, "[KZ] Show migration progress.");
	RegAdminCmd("sm_gokz_migrate_abort", CommandMigrateAbort, ADMFLAG_ROOT, "[KZ] Abort the running migration.");

	g_Step = MigrateStep_Idle;
	g_StepTimer = INVALID_HANDLE;
}

public void OnPluginEnd()
{
	Migrate_Cleanup();
}



// =====[ COMMANDS ]=====

public Action CommandMigrateDry(int client, int args)
{
	StartMigration(client, true, false);
	return Plugin_Handled;
}

public Action CommandMigrateRun(int client, int args)
{
	StartMigration(client, false, false);
	return Plugin_Handled;
}

public Action CommandMigrateNonGlobalMaps(int client, int args)
{
	StartMigration(client, true, true);
	return Plugin_Handled;
}

public Action CommandMigrateStatus(int client, int args)
{
	if (g_Step == MigrateStep_Idle)
	{
		ReplyToCommand(client, "[KZ] No migration is running.");
		return Plugin_Handled;
	}

	char stepName[64];
	GetStepName(g_Step, stepName, sizeof(stepName));
	char kind[32];
	GetRunDescription(kind, sizeof(kind));
	int elapsed = GetTime() - g_StartTime;
	ReplyToCommand(client, "[KZ] Migration (%s) step %s, cursor %d, %d seconds elapsed.", kind, stepName, g_Cursor, elapsed);
	ReplyToCommand(client, "[KZ] Loaded: %d maps, %d courses, %d players, %d times, %d replay files.", ListLength(g_Maps), ListLength(g_Courses), ListLength(g_Players), ListLength(g_Times), ListLength(g_Replays));
	ReplyToCommand(client, "[KZ] Log: %s", gC_LogPath);
	return Plugin_Handled;
}

public Action CommandMigrateAbort(int client, int args)
{
	if (g_Step == MigrateStep_Idle)
	{
		ReplyToCommand(client, "[KZ] No migration is running.");
		return Plugin_Handled;
	}
	Migrate_Log("Migration aborted by %L.", client);
	Migrate_Cleanup();
	ReplyToCommand(client, "[KZ] Migration aborted.");
	return Plugin_Handled;
}



// =====[ STEP MACHINE ]=====

static void StartMigration(int client, bool dryRun, bool listMapsOnly)
{
	if (g_Step != MigrateStep_Idle)
	{
		ReplyToCommand(client, "[KZ] A migration is already running. Use sm_gokz_migrate_status or sm_gokz_migrate_abort.");
		return;
	}

	gB_DryRun = dryRun;
	gB_ListMapsOnly = listMapsOnly;
	g_ListUserID = GetCommandUserID(client);
	g_StartTime = GetTime();
	CreateLists();
	OpenLog();

	char kind[32];
	GetRunDescription(kind, sizeof(kind));
	Migrate_Log("========================================================");
	Migrate_Log("GOKZ migration started by %L (%s).", client, kind);
	Migrate_Log("Reports: %s*", gC_ReportPrefix);
	ReplyToCommand(client, "[KZ] Migration started (%s). Follow the server console or %s", kind, gC_LogPath);

	DisableHibernation();
	SetStep(MigrateStep_Connect);
	g_StepTimer = CreateTimer(0.05, Timer_Step, _, TIMER_REPEAT);
}

static int GetCommandUserID(int client)
{
	if (client == 0)
	{
		return 0;
	}
	return GetClientUserId(client);
}

static void GetRunDescription(char[] buffer, int maxlength)
{
	if (gB_ListMapsOnly)
	{
		strcopy(buffer, maxlength, "map list only");
		return;
	}
	if (gB_DryRun)
	{
		strcopy(buffer, maxlength, "dry run");
		return;
	}
	strcopy(buffer, maxlength, "REAL RUN");
}

static void DisableHibernation()
{
	ConVar hibernate = FindConVar("sv_hibernate_when_empty");
	if (hibernate == null)
	{
		return;
	}
	g_HibernateWasEnabled = hibernate.BoolValue;
	if (!g_HibernateWasEnabled)
	{
		return;
	}
	hibernate.BoolValue = false;
	Migrate_Log("Disabled sv_hibernate_when_empty for the duration of the migration so the server keeps ticking without players.");
}

static void RestoreHibernation()
{
	if (!g_HibernateWasEnabled)
	{
		return;
	}
	g_HibernateWasEnabled = false;
	ConVar hibernate = FindConVar("sv_hibernate_when_empty");
	if (hibernate == null)
	{
		return;
	}
	hibernate.BoolValue = true;
	Migrate_Log("Restored sv_hibernate_when_empty.");
}

public Action Timer_Step(Handle timer)
{
	if (g_Step == MigrateStep_Idle || g_Step == MigrateStep_Done)
	{
		g_StepTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}

	Progress_Print();
	g_InStepTimer = true;
	bool finished = RunStep(g_Step);
	g_InStepTimer = false;
	if (g_Step == MigrateStep_Idle)
	{
		g_StepTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	if (finished)
	{
		AdvanceStep();
	}
	return Plugin_Continue;
}

static bool RunStep(MigrateStep step)
{
	switch (step)
	{
		case MigrateStep_Connect: return Step_Connect();
		case MigrateStep_FetchGlobalMaps: return Step_FetchGlobalMaps();
		case MigrateStep_LoadMaps: return Step_LoadMaps();
		case MigrateStep_LoadCourses: return Step_LoadCourses();
		case MigrateStep_LoadPlayers: return Step_LoadPlayers();
		case MigrateStep_LoadTimes: return Step_LoadTimes();
		case MigrateStep_LoadPositions: return Step_LoadPositions();
		case MigrateStep_AnalyzeMaps: return Step_AnalyzeMaps();
		case MigrateStep_AnalyzeCourses: return Step_AnalyzeCourses();
		case MigrateStep_AnalyzeTimes: return Step_AnalyzeTimes();
		case MigrateStep_AnalyzePlayers: return Step_AnalyzePlayers();
		case MigrateStep_AnalyzeHanging: return Step_AnalyzeHanging();
		case MigrateStep_AssignMapIDs: return Step_AssignMapIDs();
		case MigrateStep_AssignTimeIDs: return Step_AssignTimeIDs();
		case MigrateStep_ScanDirectories: return Step_ScanDirectories();
		case MigrateStep_ParseReplays: return Step_ParseReplays();
		case MigrateStep_MatchReplays: return Step_MatchReplays();
		case MigrateStep_WipeOutput: return Step_WipeOutput();
		case MigrateStep_InsertPlayers: return Step_InsertPlayers();
		case MigrateStep_InsertMaps: return Step_InsertMaps();
		case MigrateStep_InsertTimes: return Step_InsertTimes();
		case MigrateStep_InsertPositions: return Step_InsertPositions();
		case MigrateStep_ImportReplays: return Step_ImportReplays();
		case MigrateStep_ReportMaps: return Step_ReportMaps();
		case MigrateStep_ReportPlayers: return Step_ReportPlayers();
		case MigrateStep_ReportTimes: return Step_ReportTimes();
		case MigrateStep_ReportReplays: return Step_ReportReplays();
		case MigrateStep_Summary: return Step_Summary();
		case MigrateStep_ListMaps: return Step_ListMaps();
	}
	return true;
}

static void AdvanceStep()
{
	char stepName[64];
	GetStepName(g_Step, stepName, sizeof(stepName));
	Migrate_Log("Step %s finished in %d seconds.", stepName, GetTime() - g_StepStartTime);

	MigrateStep next = NextStep(g_Step);
	if (next == MigrateStep_Done)
	{
		Migrate_Log("Migration finished in %d seconds. Log: %s", GetTime() - g_StartTime, gC_LogPath);
		Migrate_Cleanup();
		return;
	}
	SetStep(next);
}

static MigrateStep NextStep(MigrateStep step)
{
	if (step == MigrateStep_Summary)
	{
		return MigrateStep_Done;
	}
	if (gB_ListMapsOnly && step == MigrateStep_LoadMaps)
	{
		return MigrateStep_ListMaps;
	}
	bool skipOutput = gB_DryRun && step == MigrateStep_MatchReplays;
	if (skipOutput)
	{
		return MigrateStep_ReportMaps;
	}
	return view_as<MigrateStep>(view_as<int>(step) + 1);
}

static void SetStep(MigrateStep step)
{
	g_Step = step;
	g_Cursor = 0;
	g_LastID = 0;
	g_BatchNumber = 0;
	g_StepStartTime = GetTime();
	char stepName[64];
	GetStepName(step, stepName, sizeof(stepName));
	Migrate_Log("Step %s started.", stepName);
}

void Migrate_Fail(const char[] format, any ...)
{
	char message[1024];
	VFormat(message, sizeof(message), format, 2);
	Migrate_Log("FATAL: %s", message);
	LogError("GOKZ migration failed: %s", message);
	Migrate_Log("Migration stopped after %d seconds. Log: %s", GetTime() - g_StartTime, gC_LogPath);
	Migrate_Cleanup();
}

void Migrate_Cleanup()
{
	g_Step = MigrateStep_Idle;
	if (g_StepTimer != INVALID_HANDLE && !g_InStepTimer)
	{
		KillTimer(g_StepTimer);
	}
	g_StepTimer = INVALID_HANDLE;
	RestoreHibernation();
	CloseReports();
	if (gH_InputDB != null)
	{
		delete gH_InputDB;
	}
	if (gH_OutputDB != null)
	{
		delete gH_OutputDB;
	}
	DeleteLists();
}

void GetStepName(MigrateStep step, char[] buffer, int maxlength)
{
	static const char names[][] =
	{
		"Idle", "Connect", "FetchGlobalMaps", "LoadMaps", "LoadCourses", "LoadPlayers", "LoadTimes", "LoadPositions",
		"AnalyzeMaps", "AnalyzeCourses", "AnalyzeTimes", "AnalyzePlayers", "AnalyzeHanging", "AssignMapIDs", "AssignTimeIDs",
		"ScanDirectories", "ParseReplays", "MatchReplays",
		"WipeOutput", "InsertPlayers", "InsertMaps", "InsertTimes", "InsertPositions", "ImportReplays",
		"ReportMaps", "ReportPlayers", "ReportTimes", "ReportReplays", "Summary", "ListMaps", "Done"
	};
	strcopy(buffer, maxlength, names[view_as<int>(step)]);
}



// =====[ LISTS ]=====

static void CreateLists()
{
	g_Maps = new ArrayList(sizeof(MigrateMap));
	g_Courses = new ArrayList(sizeof(MigrateCourse));
	g_Players = new ArrayList(sizeof(MigratePlayer));
	g_Times = new ArrayList(sizeof(MigrateTime));
	g_VBPositions = new ArrayList(sizeof(MigrateVBPosition));
	g_StartPositions = new ArrayList(sizeof(MigrateStartPosition));
	g_Replays = new ArrayList(sizeof(MigrateReplay));
	g_DirectoryQueue = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_FileQueue = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_MapIndexByName = new StringMap();
	g_MapIndexByID = new StringMap();
	g_CourseIndexByKey = new StringMap();
	g_CourseIndexByID = new StringMap();
	g_PlayerIndexByID = new StringMap();
	g_TimeIndexesByKey = new StringMap();
	g_GlobalMaps = new StringMap();
	g_GlobalStems = new StringMap();
	g_Renames = new StringMap();
}

static void DeleteLists()
{
	delete g_Maps;
	delete g_Courses;
	delete g_Players;
	delete g_Times;
	delete g_VBPositions;
	delete g_StartPositions;
	delete g_Replays;
	delete g_DirectoryQueue;
	delete g_FileQueue;
	delete g_MapIndexByName;
	delete g_MapIndexByID;
	delete g_CourseIndexByKey;
	delete g_CourseIndexByID;
	delete g_PlayerIndexByID;
	delete g_TimeIndexesByKey;
	delete g_GlobalMaps;
	DeleteListMap(g_GlobalStems);
	g_GlobalStems = null;
	delete g_Renames;
}

static void DeleteListMap(StringMap map)
{
	if (map == null)
	{
		return;
	}
	StringMapSnapshot snapshot = map.Snapshot();
	for (int i = 0; i < snapshot.Length; i++)
	{
		char key[128];
		snapshot.GetKey(i, key, sizeof(key));
		ArrayList list;
		map.GetValue(key, list);
		delete list;
	}
	delete snapshot;
	delete map;
}

int ListLength(ArrayList list)
{
	if (list == null)
	{
		return 0;
	}
	return list.Length;
}

ArrayList ListMapGet(StringMap map, const char[] key)
{
	ArrayList list;
	if (!map.GetValue(key, list))
	{
		return null;
	}
	return list;
}

int ChainIndex(StringMap headByKey, const char[] key, int index)
{
	int previousHead = -1;
	headByKey.GetValue(key, previousHead);
	headByKey.SetValue(key, index);
	return previousHead;
}

void IntKey(int value, char[] buffer, int maxlength)
{
	IntToString(value, buffer, maxlength);
}
