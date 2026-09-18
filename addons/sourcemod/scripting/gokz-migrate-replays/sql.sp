#define MIGRATE_PAGE_SIZE 5000



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
