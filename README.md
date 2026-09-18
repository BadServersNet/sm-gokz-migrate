# gokz-migrate

One-time [SourceMod](https://www.sourcemod.net/about.php) migration plugins that move a legacy [GOKZ](https://github.com/KZGlobalTeam/gokz) server onto the replay store version of GOKZ.

## Plugins

### gokz-migrate

One-time migration tool. Reads a legacy gokz database (`gokz-input` in `databases.cfg`), drops maps that are no longer on the Global API, purges players without times or jumps and rebuilds the `gokz` database with the same IDs. The input database is never modified, so the migration can be repeated. **Requires gokz-localdb and the GlobalAPI plugin. Unload it once the migration is done.**

### gokz-migrate-replays

One-time migration tool. Scans a legacy replay folder (`_runs`, `_tempRuns`, `_jumps`, `_cheaters`), matches every replay file to its Times or Jumpstats row in the legacy `gokz-input` database, checks that the row exists in the migrated `gokz` database and queues the matched files for upload to the replay store under their migrated map name. The input folder is never modified. Run it after gokz-migrate. **Requires gokz-localdb and gokz-replays. Unload it once the migration is done.**

## Commands

### gokz-migrate

 * `sm_gokz_migrate_dry` - Analyze the `gokz-input` database without writing anything. Writes a log and CSV reports to `addons/sourcemod/logs/gokz-migrate/`.
 * `sm_gokz_migrate_run` - Wipe the `gokz` database and migrate the legacy data into it.
 * `sm_gokz_migrate_nonglobal_maps` - List every map in the `gokz-input` database that is not on the Global API map list, with the rename rule or similar global map names for each. Only the input database is read.
 * `sm_gokz_migrate_status` - Show the current migration step.
 * `sm_gokz_migrate_abort` - Abort the running migration.

### gokz-migrate-replays

 * `sm_gokz_migrate_replays_dry` - Match every replay file in `gokz_migrate_replays_input_dir` against the `gokz-input` and `gokz` databases without importing anything. Writes a log and CSV reports to `addons/sourcemod/logs/gokz-migrate-replays/`.
 * `sm_gokz_migrate_replays_run` - Import every matched replay into the replay store and queue it for upload through gokz-replays. Run it after `sm_gokz_migrate_run`.
 * `sm_gokz_migrate_replays_status` - Show the current replay migration step.
 * `sm_gokz_migrate_replays_abort` - Abort the running replay migration.

## Building

The GOKZ, GlobalAPI, MovementAPI and sm-json includes the plugins need are vendored in `addons/sourcemod/scripting/include`, so only the SourceMod compiler is required. Run `spcomp` from `addons/sourcemod/scripting`:

```bash
spcomp gokz-migrate.sp
```

```bash
spcomp gokz-migrate-replays.sp
```

The `gokz` includes come from the replay store version of GOKZ. Copy them again if `gokz/replays.inc` or `gokz/localdb.inc` change there.

## Installing

Copy `addons` and `cfg` into the server's `csgo` directory alongside GOKZ, add a `gokz-input` entry for the legacy database to `databases.cfg`, and load the plugins only for the duration of the migration.
