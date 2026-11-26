#!/usr/bin/env bash
# desc: Reload the in-database JVM after a change of the database image

set -e

# A change of the database image keeps the old datafiles. The in-database JVM
# then stops without a message. Every Java call raises
#   ORA-29548: ... could not find classes.bin version that matches
#              executable version
# while dba_registry still reports JAVAVM as VALID. The status flag is stale, so
# the only reliable test is to call into the JVM.
#
# This script tests the JVM. If it is broken, it runs update_javavm_db.sql in
# every container. initjvm.sql is the wrong tool: it refuses with ORA-29539.
# It then refreshes the JAVAVM status flag, because update_javavm_db.sql leaves
# it INVALID with a working JVM.
#
# A healthy JVM is not touched. The reload installs about 33k Java classes.
# `--force` reloads it anyway.

source ./scripts/util/load_env.sh

FORCE=false
case "${1:-}" in
  "") ;;
  --force) FORCE=true ;;
  *)
    echo "Usage: $0 [--force]" >&2
    exit 1
    ;;
esac

# Run SQL from stdin as SYSDBA inside the container (OS authentication).
sqlsys() {
  # The single quotes are intended: $ORACLE_HOME must expand inside the container.
  # shellcheck disable=SC2016
  $CONTAINER_CLI exec -i "$CONTAINER_NAME" bash -c \
    'source /home/oracle/.bashrc 2>/dev/null; $ORACLE_HOME/bin/sqlplus -S -L / as sysdba'
}

jvm_is_broken() {
  sqlsys <<'SQL' | grep -q 'JVM_BROKEN'
set pages 0 feed off head off serveroutput on
declare v varchar2(4000);
begin
  v := dbms_java.longname('TEST');
exception when others then
  dbms_output.put_line('JVM_BROKEN');
end;
/
exit
SQL
}

if [ "$FORCE" = "false" ] && ! jvm_is_broken; then
  echo "The in-database JVM works. Nothing to do. Use --force to reload it anyway."
  exit 0
fi

echo "Reloading the in-database JVM in every container. This needs some minutes."

# catcon.pl reaches CDB$ROOT, PDB$SEED and every PDB. PDB$SEED needs
# --force_pdb_mode "READ WRITE".
$CONTAINER_CLI exec "$CONTAINER_NAME" bash -c "
source /home/oracle/.bashrc 2>/dev/null
mkdir -p /tmp/fixjvm && cd /tmp/fixjvm
\$ORACLE_HOME/perl/bin/perl \$ORACLE_HOME/rdbms/admin/catcon.pl \
  -u sys/$ORACLE_PASSWORD \
  --force_pdb_mode 'READ WRITE' \
  -b fixjvm \
  -d \$ORACLE_HOME/javavm/install \
  -l /tmp/fixjvm \
  update_javavm_db.sql
" >/dev/null

# Each container needs its own session. The validation procedure recompiles its
# own packages, and a second call in the same session fails with ORA-04061.
containers=$(sqlsys <<'SQL' | tr -d '\r ' | grep -E '^[A-Za-z][A-Za-z0-9_$]*$' || true
set pages 0 feed off head off
select 'CDB$ROOT' from dual
union all
select name from v$pdbs where open_mode = 'READ WRITE';
exit
SQL
)

root_container="CDB\$ROOT"
for con in ${containers:-$root_container}; do
  sqlsys <<SQL >/dev/null
alter session set container = $con;
begin initjvmaux.validate_javavm; end;
/
exit
SQL
done

if jvm_is_broken; then
  echo "Error: the in-database JVM is still broken. See /tmp/fixjvm/*.log in the container." >&2
  exit 1
fi

echo "The in-database JVM works."
