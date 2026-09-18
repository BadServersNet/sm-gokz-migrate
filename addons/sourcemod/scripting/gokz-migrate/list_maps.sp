// =====[ STEP ]=====

bool Step_ListMaps()
{
	int client = GetClientOfUserId(g_ListUserID);
	int missing = 0;
	for (int i = 0; i < g_Maps.Length; i++)
	{
		MigrateMap map;
		g_Maps.GetArray(i, map);
		char lower[64];
		String_ToLower(map.name, lower, sizeof(lower));
		bool validated;
		if (IsGlobalMap(lower, validated))
		{
			continue;
		}
		missing++;
		ListMissingMap(client, map, lower);
	}
	ListReply(client, "%d of %d maps in the gokz-input database are not on the global map list.", missing, g_Maps.Length);
	return true;
}



// =====[ PRIVATE ]=====

static void ListMissingMap(int client, MigrateMap map, const char[] lower)
{
	char newName[64];
	bool renamed = g_Renames.GetString(lower, newName, sizeof(newName));
	if (renamed)
	{
		bool validated;
		bool targetGlobal = IsGlobalMap(newName, validated);
		ListReply(client, "%s (MapID %d) is renamed to %s%s", map.name, map.mapID, newName, targetGlobal ? "" : ", which is not global either");
		return;
	}

	char candidates[256];
	FindRenameCandidates(lower, candidates, sizeof(candidates));
	if (candidates[0] == '\0')
	{
		ListReply(client, "%s (MapID %d)", map.name, map.mapID);
		return;
	}
	ListReply(client, "%s (MapID %d), similar global maps: %s", map.name, map.mapID, candidates);
}

static void ListReply(int client, const char[] format, any ...)
{
	char message[1024];
	VFormat(message, sizeof(message), format, 3);
	Migrate_Log("%s", message);
	if (client == 0)
	{
		return;
	}
	PrintToConsole(client, "[KZ] %s", message);
}
