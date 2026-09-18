#include <sourcemod>

#include <gokz/core>
#include <gokz/localdb>
#include <gokz/replays>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 1048576



public Plugin myinfo =
{
	name = "GOKZ Migrate Replays",
	author = "BuSheey",
	description = "One-time import of a legacy gokz replay folder into the replay store",
	version = GOKZ_VERSION,
	url = GOKZ_SOURCE_URL
};

enum MigrateStep
{
	MigrateStep_Idle = 0,
	MigrateStep_Connect,
	MigrateStep_LoadMaps,
	MigrateStep_LoadCourses,
	MigrateStep_LoadPlayers,
	MigrateStep_LoadTimes,
	MigrateStep_LoadJumps,
	MigrateStep_LoadMigratedTimes,
	MigrateStep_LoadMigratedJumps,
	MigrateStep_ScanDirectories,
	MigrateStep_ParseReplays,
	MigrateStep_MatchReplays,
	MigrateStep_ImportReplays,
	MigrateStep_ReportTimes,
	MigrateStep_ReportJumps,
	MigrateStep_ReportReplays,
	MigrateStep_Summary,
	MigrateStep_Done
};

enum ReplayCategory
{
	ReplayCategory_Runs = 0,
	ReplayCategory_TempRuns,
	ReplayCategory_Jumps,
	ReplayCategory_Cheaters,
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
	MatchStatus_Cheater,
	MatchStatus_Unreadable,
	MatchStatus_UnsupportedType
};

enum struct LegacyMap
{
	int mapID;
	char name[64];
}

enum struct LegacyCourse
{
	int mapCourseID;
	int mapID;
	int course;
}

enum struct LegacyTime
{
	int timeID;
	int steamID;
	int mapCourseID;
	int mode;
	int style;
	int runTime;
	int teleports;
	int created;
	int replayIndex;
}

enum struct LegacyJump
{
	int jumpID;
	int steamID;
	int jumpType;
	int mode;
	int distance;
	int isBlockJump;
	int block;
	int created;
	int replayIndex;
}

enum struct MigrateReplay
{
	char path[PLATFORM_MAX_PATH];
	ReplayCategory category;
	int formatVersion;
	int replayType;
	char map[64];
	int steamID;
	int mode;
	int style;
	int timestamp;
	int tickCount;
	int fileSize;
	int course;
	float time;
	int teleports;
	int jumpType;
	float distance;
	int block;
	int strafes;
	MatchStatus status;
	int recordID;
	int recordIndex;
	char targetMap[64];
	bool imported;
	char key[RP_MAX_KEY_LENGTH];
	char note[192];
}

Database gH_InputDB;
Database gH_OutputDB;
bool gB_DryRun;
MigrateStep g_Step;
Handle g_StepTimer;
int g_StartTime;
int g_StepStartTime;
int g_Cursor;
int g_LastID;
bool g_InStepTimer;
bool g_HibernateWasEnabled;

ArrayList g_Maps;
ArrayList g_Courses;
ArrayList g_Times;
ArrayList g_Jumps;
ArrayList g_Replays;
ArrayList g_DirectoryQueue;
ArrayList g_FileQueue;

StringMap g_MapIndexByName;
StringMap g_MapIndexByID;
StringMap g_CourseIndexByKey;
StringMap g_CourseIndexByID;
StringMap g_PlayerIDs;
StringMap g_TimeIndexesByKey;
StringMap g_JumpIndexesByKey;
StringMap g_MigratedTimeMaps;
StringMap g_MigratedJumpIDs;

char gC_InputDirectory[PLATFORM_MAX_PATH];
char gC_LogPath[PLATFORM_MAX_PATH];
char gC_ReportPrefix[PLATFORM_MAX_PATH];

ConVar gCV_gokz_migrate_replays_input_dir;
ConVar gCV_gokz_migrate_replays_include_cheaters;

#include "gokz-migrate-replays/log.sp"
#include "gokz-migrate-replays/sql.sp"
#include "gokz-migrate-replays/connect.sp"
#include "gokz-migrate-replays/load.sp"
#include "gokz-migrate-replays/scan.sp"
#include "gokz-migrate-replays/match.sp"
#include "gokz-migrate-replays/import.sp"
#include "gokz-migrate-replays/report.sp"



// =====[ PLUGIN EVENTS ]=====

public void OnPluginStart()
{
	gCV_gokz_migrate_replays_input_dir = CreateConVar("gokz_migrate_replays_input_dir", "data/gokz-replays/input", "Legacy replay folder to migrate, relative to addons/sourcemod. It is never modified.");
	gCV_gokz_migrate_replays_include_cheaters = CreateConVar("gokz_migrate_replays_include_cheaters", "1", "Whether cheater replays (which have no database record) are imported into the replay store.", _, true, 0.0, true, 1.0);

	RegAdminCmd("sm_gokz_migrate_replays_dry", CommandMigrateDry, ADMFLAG_ROOT, "[KZ] Match the legacy replay folder against the databases without importing anything.");
	RegAdminCmd("sm_gokz_migrate_replays_run", CommandMigrateRun, ADMFLAG_ROOT, "[KZ] Import every matched legacy replay into the replay store and queue it for upload.");
	RegAdminCmd("sm_gokz_migrate_replays_status", CommandMigrateStatus, ADMFLAG_ROOT, "[KZ] Show replay migration progress.");
	RegAdminCmd("sm_gokz_migrate_replays_abort", CommandMigrateAbort, ADMFLAG_ROOT, "[KZ] Abort the running replay migration.");

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
	StartMigration(client, true);
	return Plugin_Handled;
}

public Action CommandMigrateRun(int client, int args)
{
	StartMigration(client, false);
	return Plugin_Handled;
}

public Action CommandMigrateStatus(int client, int args)
{
	if (g_Step == MigrateStep_Idle)
	{
		ReplyToCommand(client, "[KZ] No replay migration is running.");
		return Plugin_Handled;
	}

	char stepName[64];
	GetStepName(g_Step, stepName, sizeof(stepName));
	int elapsed = GetTime() - g_StartTime;
	ReplyToCommand(client, "[KZ] Replay migration (%s) step %s, cursor %d, %d seconds elapsed.", gB_DryRun ? "dry run" : "REAL RUN", stepName, g_Cursor, elapsed);
	ReplyToCommand(client, "[KZ] Loaded: %d maps, %d courses, %d times, %d jumps, %d replay files.", ListLength(g_Maps), ListLength(g_Courses), ListLength(g_Times), ListLength(g_Jumps), ListLength(g_Replays));
	ReplyToCommand(client, "[KZ] Log: %s", gC_LogPath);
	return Plugin_Handled;
}

public Action CommandMigrateAbort(int client, int args)
{
	if (g_Step == MigrateStep_Idle)
	{
		ReplyToCommand(client, "[KZ] No replay migration is running.");
		return Plugin_Handled;
	}
	Migrate_Log("Replay migration aborted by %L.", client);
	Migrate_Cleanup();
	ReplyToCommand(client, "[KZ] Replay migration aborted.");
	return Plugin_Handled;
}



// =====[ STEP MACHINE ]=====

static void StartMigration(int client, bool dryRun)
{
	if (g_Step != MigrateStep_Idle)
	{
		ReplyToCommand(client, "[KZ] A replay migration is already running. Use sm_gokz_migrate_replays_status or sm_gokz_migrate_replays_abort.");
		return;
	}

	gB_DryRun = dryRun;
	g_StartTime = GetTime();
	CreateLists();
	OpenLog();

	Migrate_Log("========================================================");
	Migrate_Log("GOKZ replay migration started by %L (%s).", client, dryRun ? "DRY RUN, nothing will be imported" : "REAL RUN, matched replays will be imported into the replay store");
	Migrate_Log("Input directory: %s", gC_InputDirectory);
	Migrate_Log("Reports: %s*", gC_ReportPrefix);
	ReplyToCommand(client, "[KZ] Replay migration started (%s). Follow the server console or %s", dryRun ? "dry run" : "REAL RUN", gC_LogPath);

	DisableHibernation();
	SetStep(MigrateStep_Connect);
	g_StepTimer = CreateTimer(0.05, Timer_Step, _, TIMER_REPEAT);
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
		case MigrateStep_LoadMaps: return Step_LoadMaps();
		case MigrateStep_LoadCourses: return Step_LoadCourses();
		case MigrateStep_LoadPlayers: return Step_LoadPlayers();
		case MigrateStep_LoadTimes: return Step_LoadTimes();
		case MigrateStep_LoadJumps: return Step_LoadJumps();
		case MigrateStep_LoadMigratedTimes: return Step_LoadMigratedTimes();
		case MigrateStep_LoadMigratedJumps: return Step_LoadMigratedJumps();
		case MigrateStep_ScanDirectories: return Step_ScanDirectories();
		case MigrateStep_ParseReplays: return Step_ParseReplays();
		case MigrateStep_MatchReplays: return Step_MatchReplays();
		case MigrateStep_ImportReplays: return Step_ImportReplays();
		case MigrateStep_ReportTimes: return Step_ReportTimes();
		case MigrateStep_ReportJumps: return Step_ReportJumps();
		case MigrateStep_ReportReplays: return Step_ReportReplays();
		case MigrateStep_Summary: return Step_Summary();
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
		Migrate_Log("Replay migration finished in %d seconds. Log: %s", GetTime() - g_StartTime, gC_LogPath);
		Migrate_Cleanup();
		return;
	}
	SetStep(next);
}

static MigrateStep NextStep(MigrateStep step)
{
	bool skipImport = gB_DryRun && step == MigrateStep_MatchReplays;
	if (skipImport)
	{
		return MigrateStep_ReportTimes;
	}
	return view_as<MigrateStep>(view_as<int>(step) + 1);
}

static void SetStep(MigrateStep step)
{
	g_Step = step;
	g_Cursor = 0;
	g_LastID = 0;
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
	LogError("GOKZ replay migration failed: %s", message);
	Migrate_Log("Replay migration stopped after %d seconds. Log: %s", GetTime() - g_StartTime, gC_LogPath);
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

static void GetStepName(MigrateStep step, char[] buffer, int maxlength)
{
	static const char names[][] =
	{
		"Idle", "Connect", "LoadMaps", "LoadCourses", "LoadPlayers", "LoadTimes", "LoadJumps", "LoadMigratedTimes", "LoadMigratedJumps",
		"ScanDirectories", "ParseReplays", "MatchReplays", "ImportReplays",
		"ReportTimes", "ReportJumps", "ReportReplays", "Summary", "Done"
	};
	strcopy(buffer, maxlength, names[view_as<int>(step)]);
}



// =====[ LISTS ]=====

static void CreateLists()
{
	g_Maps = new ArrayList(sizeof(LegacyMap));
	g_Courses = new ArrayList(sizeof(LegacyCourse));
	g_Times = new ArrayList(sizeof(LegacyTime));
	g_Jumps = new ArrayList(sizeof(LegacyJump));
	g_Replays = new ArrayList(sizeof(MigrateReplay));
	g_DirectoryQueue = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_FileQueue = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_MapIndexByName = new StringMap();
	g_MapIndexByID = new StringMap();
	g_CourseIndexByKey = new StringMap();
	g_CourseIndexByID = new StringMap();
	g_PlayerIDs = new StringMap();
	g_TimeIndexesByKey = new StringMap();
	g_JumpIndexesByKey = new StringMap();
	g_MigratedTimeMaps = new StringMap();
	g_MigratedJumpIDs = new StringMap();
}

static void DeleteLists()
{
	delete g_Maps;
	delete g_Courses;
	delete g_Times;
	delete g_Jumps;
	delete g_Replays;
	delete g_DirectoryQueue;
	delete g_FileQueue;
	delete g_MapIndexByName;
	delete g_MapIndexByID;
	delete g_CourseIndexByKey;
	delete g_CourseIndexByID;
	delete g_PlayerIDs;
	DeleteListMap(g_TimeIndexesByKey);
	DeleteListMap(g_JumpIndexesByKey);
	delete g_MigratedTimeMaps;
	delete g_MigratedJumpIDs;
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

void ListMapPush(StringMap map, const char[] key, int value)
{
	ArrayList list;
	if (!map.GetValue(key, list))
	{
		list = new ArrayList();
		map.SetValue(key, list);
	}
	list.Push(value);
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

void IntKey(int value, char[] buffer, int maxlength)
{
	IntToString(value, buffer, maxlength);
}
