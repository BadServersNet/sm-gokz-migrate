/*
	gokz-replays Plugin Include
	
	Website: https://bitbucket.org/kztimerglobalteam/gokz
*/

#if defined _gokz_replays_included_
#endinput
#endif
#define _gokz_replays_included_

// Bit of a hack, but need it for other plugins that depend on replays to compile
#if defined REQUIRE_PLUGIN
#undef REQUIRE_PLUGIN
#include <gokz/anticheat>
#define REQUIRE_PLUGIN
#else
#include <gokz/anticheat>
#endif



// =====[ ENUMS ]=====
enum
{
	ReplayType_Run = 0,
	ReplayType_Cheater,
	ReplayType_Jump,
	REPLAYTYPE_COUNT
};

enum ReplaySaveState
{
	ReplaySave_Enabled = 0,
	ReplaySave_Disabled
};

enum
{
	ReplayDB_Lookup_ObjectKey = 0,
	ReplayDB_Lookup_FileSize,
	ReplayDB_Lookup_InStore,
	ReplayDB_Lookup_MapName
};

enum
{
	ReplayDB_Entry_ReplayID = 0,
	ReplayDB_Entry_ReplayType,
	ReplayDB_Entry_ObjectKey,
	ReplayDB_Entry_FileSize,
	ReplayDB_Entry_InStore,
	ReplayDB_Entry_MapName,
	ReplayDB_Entry_Alias,
	ReplayDB_Entry_Created,
	ReplayDB_Entry_Code,
	ReplayDB_Entry_Mode,
	ReplayDB_Entry_RunTime,
	ReplayDB_Entry_Teleports,
	ReplayDB_Entry_Course,
	ReplayDB_Entry_JumpType,
	ReplayDB_Entry_Distance,
	ReplayDB_Entry_Block,
	ReplayDB_Entry_Strafes,
	ReplayDB_Entry_Sync,
	ReplayDB_Entry_Pre,
	ReplayDB_Entry_Max,
	ReplayDB_Entry_Rank
};

// NOTE: Replays use delta compression for storage.
// This enum is the indices of the ReplayTickData enum struct.
// NOTE: This has to match the ReplayTickData enum struct!!!
enum
{
	RPDELTA_DELTAFLAGS = 0,
	RPDELTA_DELTAFLAGS2,
	RPDELTA_VEL_X,
	RPDELTA_VEL_Y,
	RPDELTA_VEL_Z,
	RPDELTA_MOUSE_X,
	RPDELTA_MOUSE_Y,
	RPDELTA_ORIGIN_X,
	RPDELTA_ORIGIN_Y,
	RPDELTA_ORIGIN_Z,
	RPDELTA_ANGLES_X,
	RPDELTA_ANGLES_Y,
	RPDELTA_ANGLES_Z,
	RPDELTA_VELOCITY_X,
	RPDELTA_VELOCITY_Y,
	RPDELTA_VELOCITY_Z,
	RPDELTA_FLAGS,
	RPDELTA_PACKETSPERSECOND,
	RPDELTA_LAGGEDMOVEMENTVALUE,
	RPDELTA_BUTTONSFORCED,
	
	RP_V2_TICK_DATA_BLOCKSIZE
};



// =====[ STRUCTS ] =====

enum struct GeneralReplayHeader
{
	int magicNumber;
	int formatVersion;
	int replayType;
	char gokzVersion[32];
	char mapName[64];
	int mapFileSize;
	int serverIP;
	int timestamp;
    char playerAlias[MAX_NAME_LENGTH];
    int playerSteamID;
    int mode;
    int style;
	float playerSensitivity;
	float playerMYaw;
    float tickrate;
    int tickCount;
	int equippedWeapon;
	int equippedKnife;
}

enum struct JumpReplayHeader
{
	int jumpType;
	float distance;
	int blockDistance;
	int strafeCount;
	float sync;
	float pre;
	float max;
	int airtime;
}

enum struct CheaterReplayHeader
{
	ACReason ACReason;
}

enum struct RunReplayHeader
{
	float time;
	int course;
	int teleportsUsed;
}

// NOTE: Make sure to change the RPDELTA_* enum, TickDataToArray() and TickDataFromArray() when adding/removing stuff from this!!!
enum struct ReplayTickData
{
	int deltaFlags;
	int deltaFlags2;
	float vel[3];
	int mouse[2];
	float origin[3];
	float angles[3];
	float velocity[3];
	int flags;
	float packetsPerSecond;
	float laggedMovementValue;
	int buttonsForced;
}



// =====[ CONSTANTS ]=====

#define RP_DIRECTORY "data/gokz-replays" // In Path_SM
#define RP_DIRECTORY_CACHE "data/gokz-replays/cache" // In Path_SM
#define RP_DIRECTORY_OUTBOX "data/gokz-replays/outbox" // In Path_SM
#define RP_DIRECTORY_STAGING "data/gokz-replays/staging" // In Path_SM
#define RP_KEY_PREFIX_RUNS "runs"
#define RP_KEY_PREFIX_JUMPS "jumps"
#define RP_KEY_PREFIX_CHEATERS "cheaters"
#define RP_OUTBOX_MARKER_EXTENSION "pending"
#define RP_FILE_EXTENSION "replay"
#define RP_MAGIC_NUMBER 0x676F6B7A
#define RP_FORMAT_VERSION 0x02
#define RP_NAV_FILE "maps/gokz-replays.nav"
#define RP_V1_TICK_DATA_BLOCKSIZE 7
#define RP_MAX_KEY_LENGTH 192
#define RP_COPY_CHUNK_CELLS 16384
#define RP_TIMEID_WAIT_TIME 15.0
#define RP_STAGING_MAX_AGE 600
#define RP_DOWNLOAD_PROGRESS_INTERVAL 0.5
#define RP_UPLOAD_BACKOFF_BASE 5.0
#define RP_UPLOAD_BACKOFF_CAP 300.0
#define RP_MENU_LIST_COUNT 50
#define RP_PROGRESS_UPDATE_INTERVAL 0.5
#define RP_PROGRESS_POINT_SPACING 24.0
#define RP_PROGRESS_MAX_POINTS 2000
#define RP_PROGRESS_ROUTE_CANDIDATES 5
#define RP_PROGRESS_SEARCH_WINDOW 40
#define RP_PROGRESS_SNAP_DISTANCE 300.0
#define RP_PROGRESS_TOLERANCE 32.0
#define RP_MENU_MAP_COUNT 100
#define RP_CODE_LENGTH 6
#define RP_CODE_BUFFER 9
#define RP_CODE_INSERT_ATTEMPTS 3
#define RP_MAX_BOTS 4
#define RP_PLAYBACK_BREATHER_TIME 2.0
#define RP_MIN_CHEATER_REPLAY_LENGTH 30 // 30 seconds
#define RP_MAX_CHEATER_REPLAY_LENGTH 120 // 2 minutes
#define RP_MAX_BHOP_GROUND_TICKS 5
#define RP_SKIP_TIME 10 // 10 seconds
#define RP_MAX_DURATION 6451200 // 14 hours on 128 tick
#define RP_JUMP_STEP_SOUND_THRESHOLD 140.0
#define RP_PLAYER_ACCELSPEED 450.0

#define RP_MOVETYPE_MASK		(0xF)
#define RP_IN_ATTACK			(1 << 4)
#define RP_IN_ATTACK2			(1 << 5)
#define RP_IN_JUMP				(1 << 6)
#define RP_IN_DUCK				(1 << 7)
#define RP_IN_FORWARD			(1 << 8)
#define RP_IN_BACK				(1 << 9)
#define RP_IN_LEFT				(1 << 10)
#define RP_IN_RIGHT				(1 << 11)
#define RP_IN_MOVELEFT			(1 << 12)
#define RP_IN_MOVERIGHT			(1 << 13)
#define RP_IN_RELOAD			(1 << 14)
#define RP_IN_SPEED				(1 << 15)
#define RP_IN_USE				(1 << 16)
#define RP_IN_BULLRUSH			(1 << 17)
#define RP_FL_ONGROUND			(1 << 18)
#define RP_FL_DUCKING			(1 << 19)
#define RP_FL_SWIM				(1 << 20)
#define RP_UNDER_WATER			(1 << 21)
#define RP_TELEPORT_TICK		(1 << 22)
#define RP_TAKEOFF_TICK			(1 << 23)
#define RP_HIT_PERF				(1 << 24)
#define RP_SECONDARY_EQUIPPED	(1 << 25)



// =====[ FORWARDS ]=====

/**
 * Called when a run replay has been written to its final local path.
 * The file is owned by gokz-replays and must not be deleted or moved
 * by listeners; it is uploaded to the replay store and kept in the
 * local cache.
 *
 * @param client			The client ID of the player who completed the run.
 * @param replayType		The type of the replay (Run/Jump/Cheater).
 * @param map				The name of the map the run was completed on.
 * @param course			The specific course on the map the run was completed on.
 * @param timeType			The type of time (Pro/Nub).
 * @param time				The time the run was completed in.
 * @param filePath			Replay file path.
 */
forward void GOKZ_RP_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath);

/**
 * Called when a currently being recorded replay is discarded from
 * memory and recording has been stopped (without writing it to disk).
 *
 * @param client			Client index.
 */
forward void GOKZ_RP_OnReplayDiscarded(int client);

/**
 * Called when a player has ended their timer, and gokz-replays has
 * processed the time and has possibly written a replay to disk.
 *
 * @param client			Client index.
 * @param filePath			Replay file path, or "" if no replay saved.
 * @param course    		Course number.
 * @param time				Player's end time.
 * @param teleportsUsed		Number of teleports used by player.
 */
forward void GOKZ_RP_OnTimerEnd_Post(int client, const char[] filePath, int course, float time, int teleportsUsed);

/**
 * Called when a replay requested through GOKZ_RP_LoadJumpReplay or
 * GOKZ_RP_LoadRunReplay could not be played (wrong map, no bots,
 * download failed, replay missing). Lets the caller reopen its menu.
 *
 * @param client			Client index.
 */
forward void GOKZ_RP_OnPlaybackFailed(int client);



// =====[ NATIVES ]====

/**
 * Called by the HUD to get the state of the current replay.
 *
 * @param client			Client index.
 * @param info				Struct to pass the values into.
 * @return					If successful
 */
native int GOKZ_RP_GetPlaybackInfo(int client, any[] info);

/**
 * Starts playback of the replay recorded for a jumpstat PB.
 * The replay is downloaded from the replay store first if it is not cached locally.
 *
 * @param client			Client index.
 * @param jumpID			JumpID from the Jumpstats table.
 * @return					True if the request was accepted.
 */
native bool GOKZ_RP_LoadJumpReplay(int client, int jumpID);

/**
 * Starts playback of the replay recorded for a run.
 * The replay is downloaded from the replay store first if it is not cached locally.
 *
 * @param client			Client index.
 * @param timeID			TimeID from the Times table.
 * @return					True if the request was accepted.
 */
native bool GOKZ_RP_LoadRunReplay(int client, int timeID);

/**
 * Gets how far along the server record route a player is. The route is the
 * fastest main course replay of the current map. Only players whose timer is
 * running on the main course, or who just finished it, are tracked.
 *
 * @param client			Client index.
 * @param progress			Fraction of the record run's time reached (0.0 to 1.0).
 * @param rank				Position among tracked players, best first.
 * @param total				Number of tracked players.
 * @return					False if there is no route or the player is not tracked.
 */
native bool GOKZ_RP_GetProgress(int client, float &progress, int &rank, int &total);

/**
 * Called by the HUD to show the replay control menu.
 *
 * @param client			Client index.
 */
native bool GOKZ_RP_UpdateReplayControlMenu(int client);

/**
 * Copies an existing replay file into the local cache under the object key
 * that gokz-replays would have used for it and queues it for upload to the
 * replay store. The source file is left untouched. The Replays row is
 * registered once the upload completes (or immediately if the store is disabled).
 *
 * @param sourcePath		Path of the replay file to import.
 * @param replayType		The type of the replay (Run/Jump/Cheater).
 * @param recordID			TimeID for runs, JumpID for jumps, 0 for cheater replays.
 * @param steamID			SteamID32 of the player.
 * @param map				Map name used in the object key and stored as the replay's map.
 * @param timestamp			Unix timestamp used in jump and cheater keys.
 * @param mode				Movement mode used in cheater keys.
 * @param style				Movement style used in cheater keys.
 * @param key				Buffer that receives the object key.
 * @param maxlength			Size of the key buffer.
 * @return					True if the file was copied and queued.
 */
native bool GOKZ_RP_ImportReplay(const char[] sourcePath, int replayType, int recordID, int steamID, const char[] map, int timestamp, int mode, int style, char[] key, int maxlength);

/**
 * Returns the number of replay uploads that are queued or in flight.
 *
 * @return					Pending upload count.
 */
native int GOKZ_RP_GetPendingUploadCount();

/**
 * Drops every queued upload and deletes its outbox marker. Cached replay
 * files are kept. Meant for tools that rebuild the database and re-import
 * every replay afterwards.
 *
 * @return					Number of uploads dropped.
 */
native int GOKZ_RP_ClearUploadQueue();


// =====[ DEPENDENCY ]=====

public SharedPlugin __pl_gokz_replays = 
{
	name = "gokz-replays", 
	file = "gokz-replays.smx", 
	#if defined REQUIRE_PLUGIN
	required = 1, 
	#else
	required = 0, 
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_gokz_replays_SetNTVOptional()
{
	MarkNativeAsOptional("GOKZ_RP_GetPlaybackInfo");
	MarkNativeAsOptional("GOKZ_RP_LoadJumpReplay");
	MarkNativeAsOptional("GOKZ_RP_LoadRunReplay");
	MarkNativeAsOptional("GOKZ_RP_GetProgress");
	MarkNativeAsOptional("GOKZ_RP_UpdateReplayControlMenu");
	MarkNativeAsOptional("GOKZ_RP_ImportReplay");
	MarkNativeAsOptional("GOKZ_RP_GetPendingUploadCount");
	MarkNativeAsOptional("GOKZ_RP_ClearUploadQueue");
}
#endif
