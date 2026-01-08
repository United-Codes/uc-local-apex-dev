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
SET SERVEROUTPUT ON
DECLARE
  i          NUMBER := 0;
  l_count    NUMBER;
  l_cascade  VARCHAR2(20 char);
BEGIN
  <<delete_iterations>>
  LOOP
    i := i + 1;
    l_count := 0;
    
    <<objects>>
    FOR cur_rec IN (SELECT object_name, object_type 
                      FROM user_objects
                     WHERE object_type not in ('CREDENTIAL'))
    LOOP
      BEGIN
        l_count := l_count + 1;
        l_cascade := NULL;

        IF cur_rec.object_type = 'JOB' THEN
          EXECUTE IMMEDIATE 'BEGIN sys.DBMS_SCHEDULER.DROP_JOB(''' || cur_rec.object_name || ''', TRUE); END;';
          CONTINUE;
        END IF;

        IF cur_rec.object_type = 'TABLE' THEN
          l_cascade := ' CASCADE CONSTRAINTS';
        END IF;
        EXECUTE IMMEDIATE 'DROP ' || cur_rec.object_type || ' "' || cur_rec.object_name || '"' || l_cascade;
      EXCEPTION
        WHEN OTHERS THEN
          NULL;
      END;
    END LOOP objects;
    -- Comment out the following line if you are pre-10g, or want to preserve the recyclebin contents. 
    EXECUTE IMMEDIATE 'PURGE RECYCLEBIN';
    sys.DBMS_OUTPUT.put_line('Pass: ' || i || '  Drops: ' || l_count);
    EXIT delete_iterations WHEN l_count = 0 OR i >= 30;
  END LOOP delete_iterations;
END;
/
