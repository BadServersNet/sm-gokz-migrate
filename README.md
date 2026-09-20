# gokz-migrate

One-time [SourceMod](https://www.sourcemod.net/about.php) migration plugin that moves a legacy [GOKZ](https://github.com/KZGlobalTeam/gokz) server onto the replay store version of GOKZ.

## Plugin

### gokz-migrate

One-time migration tool. Reads a legacy gokz database (`gokz-input` in `databases.cfg`) and a legacy replay folder, and rebuilds the `gokz` database so that it only holds maps that are validated on the Global API, with every primary key renumbered from 1. The input database and the input folder are never modified, so the migration can be repeated. **Requires gokz-localdb and gokz-replays, and the GlobalAPI plugin when no global map file is present. Unload it once the migration is done.**

A run goes through these stages:

 1. **Analyze** - Every legacy map is checked against the validated Global API map list (`cfg/sourcemod/gokz/gokz-migrate-global-maps.txt`, or the Global API when that file is missing). Maps that are not on it are left behind together with their courses, times and positions. Jumpstats are left behind and players without times are purged.
 2. **Assign IDs** - Maps are walked one by one in legacy `MapID` order. Each kept map gets the next `MapID` and its courses get the next `MapCourseID`s in course order. Kept times then get the next `TimeID` in legacy `TimeID` order.
 3. **Match replays** - The `_runs` and `_tempRuns` folders of the replay folder are scanned (`_jumps` and `_cheaters` are skipped) and every run replay is matched to its legacy Times row. Replays of times that are not migrated are left behind.
 4. **Write** - The `gokz` tables are wiped and their `AUTO_INCREMENT` is reset. Players are inserted, then every map is moved one by one with its courses, then the times, then the saved positions, all under their new IDs.
 5. **Import replays** - Every matched replay is copied into the replay store under its new `TimeID` and migrated map name and queued for upload through gokz-replays.

The write stage keeps the old and new IDs in three tables in the `gokz` database: `MigrateMapIDs (OldMapID, NewMapID)`, `MigrateCourseIDs (OldMapCourseID, NewMapCourseID)` and `MigrateTimeIDs (OldTimeID, NewTimeID)`. They are recreated by every run and are not used by GOKZ, so drop them once the migration has been checked.

While a migration runs, the server console only shows the step messages, warnings and a `PROGRESS` line every 5 seconds with the step, its percentage, an estimate of the time left in that step and the total elapsed time. The per-row detail goes to the log file only.

Change the map after a run so gokz-localdb looks up the new `MapID` of the current map.

## Commands

 * `sm_gokz_migrate_dry` - Run the analyze, assign and match stages without writing anything. Writes a log and CSV reports, including the new IDs, to `addons/sourcemod/logs/gokz-migrate/`.
 * `sm_gokz_migrate_run` - Wipe the `gokz` database, migrate the legacy data into it and import the legacy replays.
 * `sm_gokz_migrate_nonglobal_maps` - List every map in the `gokz-input` database that is not on the Global API map list, with the rename rule or similar global map names for each. Only the input database is read.
 * `sm_gokz_migrate_status` - Show the current migration step.
 * `sm_gokz_migrate_abort` - Abort the running migration.

## ConVars

 * `gokz_migrate_replays_input_dir` - Legacy replay folder, relative to `addons/sourcemod`. Defaults to `data/gokz-replays/input`.
 * `gokz_migrate_global_maps_file` - File with one validated global map name per line.
 * `gokz_migrate_renames_file` - KeyValues file mapping old map names to their current global names.
 * `gokz_migrate_keep_cheater_players` - Whether players flagged as cheaters are kept even when they have no times.

## Building

The GOKZ, GlobalAPI, MovementAPI and sm-json includes the plugin needs are vendored in `addons/sourcemod/scripting/include`, so only the SourceMod compiler is required. Run `spcomp` from `addons/sourcemod/scripting`:

```bash
spcomp gokz-migrate.sp
```

The vendored GOKZ includes raise unused symbol warnings, so the plugin is compiled without `-E`.

The `gokz` includes come from the replay store version of GOKZ. Copy them again if `gokz/replays.inc` or `gokz/localdb.inc` change there.

## Releases

Pushes and pull requests are compiled by the `Build and release` workflow. Pushing a `v*` tag that matches `PLUGIN_VERSION` in `gokz-migrate.sp` publishes a release with the compiled plugin, its source and the `cfg` files.

## Installing

Download the latest release and copy `addons` and `cfg` into the server's `csgo` directory alongside GOKZ, add a `gokz-input` entry for the legacy database to `databases.cfg`, and load the plugin only for the duration of the migration.
