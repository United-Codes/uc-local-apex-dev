-- SQLcl's `datapump` command hardcodes KEEP_MASTER=1 in the DBMS_DATAPUMP call
-- it generates, so every job leaves its master table behind: ESQL_<n> for an
-- export, ISQL_<n> for an import. The table also keeps the job registered in
-- DBA_DATAPUMP_JOBS in state NOT RUNNING, and the next schema export picks it
-- up as an ordinary table (about 1 MB added to each later dump).
--
-- There is no way to turn KEEP_MASTER off: SQLcl 26.2.1 holds a `keepmaster`
-- entry in its internal option enum, but no command accepts it. Dropping the
-- table afterwards is the supported cleanup, and it also deregisters the job.
-- Drop both kinds.
DECLARE
  l_sql     VARCHAR2(4000 CHAR);
  l_dropped PLS_INTEGER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Starting Data Pump master table cleanup (ESQL_/ISQL_)...');
  DBMS_OUTPUT.PUT_LINE('-----------------------------');

  <<master_tables>>
  FOR tab_rec IN (SELECT table_name
                  FROM user_tables
                  WHERE REGEXP_LIKE(table_name, '^(ESQL|ISQL)_[0-9]+$'))
  LOOP
    BEGIN
      l_sql := 'DROP TABLE ' || DBMS_ASSERT.ENQUOTE_NAME(tab_rec.table_name) || ' PURGE';
      EXECUTE IMMEDIATE l_sql;
      l_dropped := l_dropped + 1;
      DBMS_OUTPUT.PUT_LINE('Dropped table ' || tab_rec.table_name);
    EXCEPTION
      WHEN OTHERS THEN
        -- One locked or in-use master table must not stop the rest.
        DBMS_OUTPUT.PUT_LINE('Skipped ' || tab_rec.table_name || ': ' || SQLERRM);
    END;
  END LOOP master_tables;

  DBMS_OUTPUT.PUT_LINE('Dropped ' || l_dropped || ' master table(s).');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
    DBMS_OUTPUT.PUT_LINE('Error occurred during processing. Please check permissions.');
END;
/
