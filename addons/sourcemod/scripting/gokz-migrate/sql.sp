#define MIGRATE_QUERY_SIZE 262144
#define MIGRATE_PAGE_SIZE 5000
#define MIGRATE_INSERT_BATCH 500

static char g_Query[MIGRATE_QUERY_SIZE];



// =====[ PUBLIC ]=====

DBResultSet Migrate_Query(Database db, const char[] query)
{
	DBResultSet results = SQL_Query(db, query);
	if (results != null)
	{
		return results;
	}
	char error[512];
	SQL_GetError(db, error, sizeof(error));
	char preview[200];
	strcopy(preview, sizeof(preview), query);
	Migrate_Fail("Query failed: %s (query starts with: %s)", error, preview);
	return null;
}

bool Migrate_Exec(Database db, const char[] query)
{
	if (SQL_FastQuery(db, query))
	{
		return true;
	}
	char error[512];
	SQL_GetError(db, error, sizeof(error));
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
	strcopy(g_Query, sizeof(g_Query), head);
}

void QueryAppend(const char[] format, any ...)
{
	int length = strlen(g_Query);
	VFormat(g_Query[length], sizeof(g_Query) - length, format, 2);
}

bool QueryFlush(Database db)
{
	return Migrate_Exec(db, g_Query);
}

int QueryLength()
{
	return strlen(g_Query);
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

void SqlTimestamp(int timestamp, char[] buffer, int maxlength)
{
	if (timestamp <= 0)
	{
		strcopy(buffer, maxlength, "NULL");
		return;
	}
	FormatEx(buffer, maxlength, "FROM_UNIXTIME(%d)", timestamp);
}
