DECLARE
  l_sql   VARCHAR2(4000 char);
BEGIN
  -- Print header for the operation
  DBMS_OUTPUT.PUT_LINE('Starting Data Pump ESQL_ tables cleanup...');
  DBMS_OUTPUT.PUT_LINE('-----------------------------');

  <<ESQL_tables>>
  FOR tab_rec IN (SELECT table_name 
                  FROM user_tables 
                  WHERE REGEXP_LIKE(table_name, '^ESQL_[0-9]+$')) 
  LOOP
    -- Drop the table
    l_sql := 'DROP TABLE ' || tab_rec.table_name || ' PURGE';
    EXECUTE IMMEDIATE l_sql;
    
    -- Report success
    DBMS_OUTPUT.PUT_LINE('Dropped table ' || tab_rec.table_name);
  END LOOP ESQL_tables;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
    DBMS_OUTPUT.PUT_LINE('Error occurred during processing. Please check permissions.');
END;
/
