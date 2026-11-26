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
-- @dblinter ignore(Core G-5010): this is a SQLcl script, dbms_output is its output
DECLARE
  l_sql     VARCHAR2(4000 CHAR);
  l_dropped PLS_INTEGER := 0;
BEGIN
  sys.DBMS_OUTPUT.PUT_LINE('Starting Data Pump master table cleanup (ESQL_/ISQL_)...');
  sys.DBMS_OUTPUT.PUT_LINE('-----------------------------');

  <<master_tables>>
  FOR tab_rec IN (SELECT table_name
                  FROM user_tables
                  WHERE REGEXP_LIKE(table_name, '^(ESQL|ISQL)_[0-9]+$')
                    -- A schema that is not in .env runs DataPump as SYS. Then the
                    -- master tables of ALL jobs are in the schema SYS, and two
                    -- jobs can run at once (import-all -j). Drop only the tables of
                    -- jobs that are finished: a table of a running job is in use,
                    -- and dropping it kills the job (ORA-39014).
                    AND (USER <> 'SYS'
                         OR EXISTS (SELECT 1 FROM user_datapump_jobs j
                                     WHERE j.job_name = table_name AND j.state = 'NOT RUNNING')))
  LOOP
    BEGIN
      l_sql := 'DROP TABLE ' || sys.DBMS_ASSERT.ENQUOTE_NAME(tab_rec.table_name) || ' PURGE';
      EXECUTE IMMEDIATE l_sql;
      l_dropped := l_dropped + 1;
      sys.DBMS_OUTPUT.PUT_LINE('Dropped table ' || tab_rec.table_name);
    EXCEPTION
      WHEN OTHERS THEN
        -- One locked or in-use master table must not stop the rest.
        sys.DBMS_OUTPUT.PUT_LINE('Skipped ' || tab_rec.table_name || ': ' || SQLERRM ||
          ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
    END;
  END LOOP master_tables;

  sys.DBMS_OUTPUT.PUT_LINE('Dropped ' || l_dropped || ' master table(s).');
EXCEPTION
  WHEN OTHERS THEN
    sys.DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
    sys.DBMS_OUTPUT.PUT_LINE('Error occurred during processing. Please check permissions.');
END;
/
