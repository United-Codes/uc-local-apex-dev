-- -----------------------------------------------------------------------------------
-- File Name    : https://oracle-base.com/dba/miscellaneous/drop_all.sql
-- Author       : Tim Hall
-- Description  : Drops all objects within the current schema.
-- Call Syntax  : @drop_all
-- Last Modified: 20/01/2006
-- Notes        : Loops a maximum of 5 times, allowing for failed drops due to dependencies.
--                Quits outer loop if no drops were atempted.
-- -----------------------------------------------------------------------------------

-- Modified by: Philipp Hartenfeller
-- @dblinter ignore(Core G-5010): this is a SQLcl script, dbms_output is its output
-- @dblinter ignore(Core G-5040): a failed drop is retried in the next pass
SET SERVEROUTPUT ON
DECLARE
  i          NUMBER := 0;
  l_count    NUMBER;
  l_cascade  VARCHAR2(20 char);
  l_sql      VARCHAR2(1000 char);
BEGIN
  <<delete_iterations>>
  LOOP
    i := i + 1;
    l_count := 0;
    
    <<objects>>
    FOR cur_rec IN (SELECT object_name, object_type 
                      FROM user_objects
                     WHERE object_type not in ('CREDENTIAL', 'INDEX', 'LOB'))
    LOOP
      BEGIN
        l_count := l_count + 1;
        l_cascade := NULL;

        IF cur_rec.object_type = 'JOB' THEN
          l_sql := 'BEGIN sys.DBMS_SCHEDULER.DROP_JOB(''' || cur_rec.object_name || ''', TRUE); END;';
          EXECUTE IMMEDIATE l_sql;
          CONTINUE;
        END IF;
        --
        if cur_rec.object_type = 'PROGRAM'
        then
           l_sql := 'begin sys.dbms_scheduler.drop_program (program_name => '''||cur_rec.object_name||''',force => true); end;';
           execute immediate l_sql;
           continue;
        end if;
        --
        if cur_rec.object_type = 'SCHEDULE'
        then
          l_sql := 'begin sys.dbms_scheduler.drop_schedule (schedule_name => '''||cur_rec.object_name||''', force => true); end;';
          execute immediate l_sql;
          continue;
        end if;
        --
        IF cur_rec.object_type = 'TABLE' THEN
          l_cascade := ' CASCADE CONSTRAINTS';
        END IF;
        l_sql := 'DROP ' || cur_rec.object_type || ' "' || cur_rec.object_name || '"' || l_cascade;
        EXECUTE IMMEDIATE l_sql;
      EXCEPTION
        WHEN OTHERS THEN
          NULL;
      END;
    END LOOP objects;
    <<queues>>
    for rec in (select queue_table
                  from user_queue_tables)
    loop
       begin
        l_count := l_count + 1;
        l_sql := 'begin sys.dbms_aqadm.drop_queue_table ('''||rec.queue_table||''', true); end;';
        execute immediate l_sql;
       exception
       when others
       then null;
       end;
    end loop queues;
    -- Comment out the following line if you are pre-10g, or want to preserve the recyclebin contents. 
    l_sql := 'PURGE RECYCLEBIN';
    EXECUTE IMMEDIATE l_sql;
    sys.DBMS_OUTPUT.put_line('Pass: ' || i || '  Drops: ' || l_count);
    EXIT delete_iterations WHEN l_count = 0 OR i >= 30;
  END LOOP delete_iterations;
END;
/
