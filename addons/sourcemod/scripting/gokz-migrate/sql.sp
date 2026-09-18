#define MIGRATE_QUERY_SIZE 262144
#define MIGRATE_PAGE_SIZE 5000
#define MIGRATE_INSERT_BATCH 500
#define MIGRATE_QUERY_ROW_RESERVE 2048

static char g_Query[MIGRATE_QUERY_SIZE];
static int g_QueryLength;



// =====[ PUBLIC ]=====

DBResultSet Migrate_Query(Database db, const char[] query)
{
	char error[512];
	SQL_LockDatabase(db);
	DBResultSet results = SQL_Query(db, query);
	if (results == null)
	{
		SQL_GetError(db, error, sizeof(error));
	}
	SQL_UnlockDatabase(db);
	if (results != null)
	{
		return results;
	}
	char preview[200];
	strcopy(preview, sizeof(preview), query);
	Migrate_Fail("Query failed: %s (query starts with: %s)", error, preview);
	return null;
}

bool Migrate_Exec(Database db, const char[] query)
{
	char error[512];
	SQL_LockDatabase(db);
	bool executed = SQL_FastQuery(db, query);
	if (!executed)
	{
		SQL_GetError(db, error, sizeof(error));
	}
	SQL_UnlockDatabase(db);
	if (executed)
	{
		return true;
	}
	char preview[200];
	strcopy(preview, sizeof(preview), query);
	Migrate_Fail("Statement failed: %s (statement starts with: %s)", error, preview);
	return false;
}

bool Migrate_FetchScalarString(Database db, const char[] query, char[] buffer, int maxlength)
{
	DBResultSet results = Migrate_Query(db, query);
	if (results == null)
	{
		return false;
	}
	bool fetched = results.FetchRow();
	if (fetched)
	{
		results.FetchString(0, buffer, maxlength);
	}
	delete results;
	return fetched;
}

int Migrate_FetchScalarInt(Database db, const char[] query)
{
	DBResultSet results = Migrate_Query(db, query);
	if (results == null)
	{
		return -1;
	}
	int value = -1;
	if (results.FetchRow())
	{
		value = results.FetchInt(0);
	}
	delete results;
	return value;
}

void QueryBegin(const char[] head)
{
	g_QueryLength = strcopy(g_Query, sizeof(g_Query), head);
}

void QueryAppend(const char[] format, any ...)
{
	int written = VFormat(g_Query[g_QueryLength], sizeof(g_Query) - g_QueryLength, format, 2);
	g_QueryLength += written;
}

bool QueryHasRoom()
{
	return g_QueryLength < sizeof(g_Query) - MIGRATE_QUERY_ROW_RESERVE;
}

bool QueryFlush(Database db)
{
	return Migrate_Exec(db, g_Query);
}

int QueryLength()
{
	return g_QueryLength;
}

void SqlString(Database db, const char[] input, bool isNull, char[] buffer, int maxlength)
{
	if (isNull)
	{
		strcopy(buffer, maxlength, "NULL");
		return;
	}
	char escaped[512];
	SQL_EscapeString(db, input, escaped, sizeof(escaped));
	FormatEx(buffer, maxlength, "'%s'", escaped);
}

void SqlCreated(int timestamp, char[] buffer, int maxlength)
{
	if (timestamp <= 0)
	{
		strcopy(buffer, maxlength, "CURRENT_TIMESTAMP");
		return;
	}
	FormatEx(buffer, maxlength, "FROM_UNIXTIME(%d)", timestamp);
}

void SqlTimestamp(int timestamp, char[] buffer, int maxlength)
{
	if (timestamp <= 0)
	{
		strcopy(buffer, maxlength, "NULL");
		return;
	}
	FormatEx(buffer, maxlength, "FROM_UNIXTIME(%d)", timestamp);
}
