set serveroutput on

-- @dblinter ignore(Core G-5010): dbms_scheduler is fine here
-- @dblinter ignore(Core G-5040): when others null is fine here

-- Same idea for the two other log tables that grow without a limit on a dev
-- database: APEX debug messages and Logger. Both jobs keep 7 days. A delete does
-- not return space to the operating system -- it stops the segment from growing.
-- The Logger job also shrinks the table, so the space returns to the tablespace.
-- shrink-space then resizes the datafile. APEX owns its debug tables, so the APEX
-- job only deletes.
--
-- APEX: apex_debug.remove_debug_by_age works per application, and it needs the
-- workspace of that application, so the job loops over all applications.
-- Messages that a scheduler job writes have no application id. APEX removes them
-- itself when it rotates its debug tables.
begin
  sys.dbms_scheduler.drop_job('UC_APEX_DEBUG_PURGE', force => true);
exception when others then
  null;
end;
/

begin
  sys.dbms_scheduler.create_job(
    job_name        => 'UC_APEX_DEBUG_PURGE',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[begin
  for a in (select application_id, workspace_id from apex_applications) loop
    apex_util.set_security_group_id(a.workspace_id);
    apex_debug.remove_debug_by_age(
      p_application_id  => a.application_id,
      p_older_than_days => 7);
  end loop;
  commit;
end;]',
    start_date      => systimestamp,
    repeat_interval => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=20',
    enabled         => true,
    auto_drop       => false,
    comments        => 'uc-local-apex-dev: keep 7 days of APEX debug messages');
  sys.dbms_output.put_line('created UC_APEX_DEBUG_PURGE');
exception when others then
  sys.dbms_output.put_line('skip UC_APEX_DEBUG_PURGE: '||sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
end;
/

-- Logger: logger.purge refuses a call from SYS (PROTECT_ADMIN_PROCS), so the job
-- deletes from LOGGER_LOGS directly in every schema that has the table. Level 1
-- (permanent) is kept, as logger.purge keeps it.
begin
  sys.dbms_scheduler.drop_job('UC_LOGGER_PURGE', force => true);
exception when others then
  null;
end;
/

begin
  sys.dbms_scheduler.create_job(
    job_name        => 'UC_LOGGER_PURGE',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[begin
  for r in (select owner from dba_tables where table_name = 'LOGGER_LOGS') loop
    begin
      execute immediate 'delete from ' || dbms_assert.enquote_name(r.owner) ||
        '.logger_logs where time_stamp < systimestamp - 7 and logger_level >= 2';
      commit;
      -- A delete keeps the segment at its largest size. Shrink the table, so the
      -- space returns to the tablespace. SHRINK SPACE needs row movement.
      begin
        execute immediate 'alter table ' || dbms_assert.enquote_name(r.owner) ||
          '.logger_logs enable row movement';
        execute immediate 'alter table ' || dbms_assert.enquote_name(r.owner) ||
          '.logger_logs shrink space cascade';
      exception when others then
        null;
      end;
    exception when others then
      null;
    end;
  end loop;
end;]',
    start_date      => systimestamp,
    repeat_interval => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=25',
    enabled         => true,
    auto_drop       => false,
    comments        => 'uc-local-apex-dev: keep 7 days of Logger logs');
  sys.dbms_output.put_line('created UC_LOGGER_PURGE');
exception when others then
  sys.dbms_output.put_line('skip UC_LOGGER_PURGE: '||sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
end;
/
