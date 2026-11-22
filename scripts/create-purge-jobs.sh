#!/usr/bin/env bash
# desc: Create the jobs that purge old APEX debug messages and Logger logs (7 days)

set -e

# after-first-db-start.sh creates these jobs on a new install. An installed
# database does not run that script again, so this command creates them there.
# It is safe to run again: the SQL drops each job before it creates it.
source ./scripts/util/load_env.sh

sql -name "$DB_CONN_NAME" <<SQL
@./scripts/sql/create_purge_jobs.sql

begin
  dbms_scheduler.run_job('UC_APEX_DEBUG_PURGE', use_current_session => true);
  dbms_scheduler.run_job('UC_LOGGER_PURGE', use_current_session => true);
  dbms_output.put_line('initial purge done');
exception when others then
  dbms_output.put_line('skip initial purge: '||sqlerrm);
end;
/
SQL

echo "A delete does not return space to the operating system."
echo "To reclaim the space, run the shrink-space script."
