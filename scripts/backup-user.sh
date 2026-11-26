#!/usr/bin/env bash
# desc: DataPump-export a single schema incl. its APEX workspace and apps

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh
source ./scripts/util/schema-access.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi
USERNAME=$1

# A schema that is not in .env was made by hand. The password is unknown.
# DataPump and the ORDS export run as SYS. Only the APEX export needs the owner:
# if the schema has an APEX workspace, the owner gets a temporary password
# (schema-access.sh), and the old hash is put back at the end, also if this
# script fails.
if user_in_env_bool "$USERNAME"; then
  DISCOVERED=false
else
  DISCOVERED=true
fi

USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

# DataPump runs as the owner for a schema from .env. For a schema that is not in
# .env it runs as SYS. SYS is exempt from VPD and Data Redaction policies. An
# export by the owner silently leaves out the rows that a policy hides, and it
# drops the policies themselves.
DP_CONN_NAME="$USER_DB_CONN_NAME"
if [ "$DISCOVERED" = true ]; then
  DP_CONN_NAME="$DB_CONN_NAME"
fi

EXPORT_DIR="./backups/export"
APEX_DIR="${EXPORT_DIR}/apex/${USERNAME_LOWER}"
ORDS_DIR="${EXPORT_DIR}/ords/${USERNAME_LOWER}"

mkdir -p "$EXPORT_DIR"

# SQLcl hardcodes KEEP_MASTER=1 when it builds the DBMS_DATAPUMP call, so every
# job leaves its ESQL_<n> master table in the schema. There is no switch for it:
# SQLcl carries a `keepmaster` entry in its internal option enum, but it is not
# wired to `datapump export`, `datapump import` or `set datapump` (26.2.1 answers
# "Option not recognized"). Cleaning up afterwards is the only lever. Do it from
# a trap so a failure in the APEX or ORDS step below cannot skip it -- leftovers
# add roughly 1 MB to every later dump of the same schema, because the next
# export picks them up as ordinary tables.
drop_dp_master_tables() {
  sql -S -name "$DP_CONN_NAME" <<'SQL' || true
    set serveroutput on size unlimited feedback off
    @./scripts/sql/drop_dp_tables.sql
    exit;
SQL
}
ACCESS_BEGUN=false
cleanup() {
  drop_dp_master_tables
  if [ "$ACCESS_BEGUN" = true ]; then schema_access_end "$USERNAME"; fi
}
trap cleanup EXIT

# Rotate the previous dump to _bkp before the export. A failed export leaves no
# new .dmp, so the next run skips the rotation and _bkp survives two failures in
# a row. (A run that ends on a fatal DataPump error leaves a cut-off .dmp; the
# next run rotates it over _bkp.)
if [ -f "${EXPORT_DIR}/${USERNAME_LOWER}.dmp" ]; then
  rm -f "${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp"
  mv "${EXPORT_DIR}/${USERNAME_LOWER}.dmp" "${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp"
  mv -f "${EXPORT_DIR}/${USERNAME_LOWER}.log" "${EXPORT_DIR}/${USERNAME_LOWER}_bkp.log" 2>/dev/null || true
fi

# Delete the dump and log of the last run inside the container. DataPump would
# otherwise stop with ORA-27038 (file exists) and, after a failed job, an old
# dump would still be there for the pull. Also keeps the container export
# directory from growing with every run.
$CONTAINER_CLI exec "$CONTAINER_NAME" bash -c \
  "rm -f /opt/oracle/oradata/datapump/export/${USERNAME_LOWER}.dmp /opt/oracle/oradata/datapump/export/${USERNAME_LOWER}.log" || true

# `-filesize 20GB` is not cosmetic. SQLcl caps one dump file at 500MB by default.
# The export writes one file without a %U wildcard, so a schema above 500MB
# stops with ORA-39095 (dump file space exhausted) and a truncated dump. The
# edition limit is 12GB of data, so 20GB can never be reached. SQLcl rejects
# the short form `20G`; write `20GB`.
#
# The first `datapump` command of any SQLcl session fails with
#   Value DATA_PUMP_DIR is not valid for Parameter directory
# no matter what -directory was passed (reproduced on SQLcl 26.2.1); the second
# one works. This block used to be the real export written out twice, which
# worked for the same reason -- the first copy always failed -- but it printed
# an alarming error every run, and it would export everything twice on the day
# Oracle fixes the bug. `-noexec TRUE` only validates and generates PL/SQL, so
# the warm-up costs nothing and can never do work. Do not remove it.
#
# `-version latest` is not cosmetic. DataPump silently drops whole object types
# that the requested metadata version cannot represent, and the job still
# reports success. Measured on 23.26.2 with -version 11.0.0: MLE_MODULE,
# SQL_DOMAIN, DOMAIN_ASSOCIATION, IDENTITY_COLUMN and VECTOR_INDEX all vanished
# without an error. Never lower this, and never let it fall back to the SQLcl
# default of COMPATIBLE.
sql -name "$DP_CONN_NAME" <<SQL
    select user from dual;

    prompt == SQLcl warm-up. The next "DATA_PUMP_DIR is not valid" message is
    prompt == expected and harmless. The real export follows it.
    datapump export -noexec TRUE

    prompt == Exporting $USERNAME_UPPER
    datapump export -
     -schemas $USERNAME_UPPER -
     -directory DATAPUMP_EXPORT_DIR -
     -dumpdirectory DATAPUMP_EXPORT_DIR -
     -dumpfile $USERNAME_LOWER.dmp -
     -logfile $USERNAME_LOWER.log -
     -version latest -
     -filesize 20GB

    exit;
SQL

# Pull only this schema's files. The pull fails if the container has no dump,
# and that is the point: the old whole-tree pull could return a STALE dump of an
# earlier run and let a failed export look like a success.
if ! ./scripts/sync-backups-folder.sh pull "$USERNAME_LOWER"; then
  echo "ERROR: the export of $USERNAME_UPPER produced no dump in the container" >&2
  echo "       the previous dump is still at ${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp" >&2
  exit 1
fi

if [ ! -s "${EXPORT_DIR}/${USERNAME_LOWER}.dmp" ]; then
  echo "ERROR: no dump produced at ${EXPORT_DIR}/${USERNAME_LOWER}.dmp" >&2
  echo "       the previous dump is still at ${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp" >&2
  exit 1
fi

# DataPump skips the rows of a table that it cannot unload, and the job still
# "completes". Example: ORA-30657 on a table with SQL domains and an invisible
# virtual column (23.26.3). Show it, and add it to the list that rebuild shows
# before it deletes the database.
DP_LOG="${EXPORT_DIR}/${USERNAME_LOWER}.log"
# A job that stops on a fatal error (for example ORA-39095) leaves a dump that
# is not empty but is cut off. "completed with N error" below does not match it.
if [ -f "$DP_LOG" ] && grep -q 'stopped due to fatal error' "$DP_LOG"; then
  echo "ERROR: the DataPump job for $USERNAME_UPPER stopped on a fatal error. The dump is not complete:" >&2
  grep -E '^ORA-' "$DP_LOG" | sed 's/^/  /' >&2
  echo "       the previous dump is still at ${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp" >&2
  exit 1
fi
if [ -f "$DP_LOG" ] && grep -q 'completed with [0-9]* error' "$DP_LOG"; then
  echo "WARNING: DataPump reported errors for $USERNAME_UPPER. See $DP_LOG:" >&2
  grep -E '^ORA-' "$DP_LOG" | sed 's/^/  /' >&2
  mkdir -p "${EXPORT_DIR}/recovery"
  awk '/^ORA-31693:/ { split($0, a, "\""); obj = a[2] "." a[4]; getline; print "Table " obj ": DataPump skipped the rows (" substr($0, 1, 9) "). Copy them another way, for example with a CSV unload" }' \
    "$DP_LOG" >>"${EXPORT_DIR}/recovery/unrecoverable.txt"
  if ! grep -q '^ORA-31693:' "$DP_LOG"; then
    echo "DataPump export of $USERNAME_UPPER: $(grep -c '^ORA-' "$DP_LOG") errors. See $DP_LOG" >>"${EXPORT_DIR}/recovery/unrecoverable.txt"
  fi
fi

# Resolve the APEX workspace before exporting anything. A schema does not have
# to belong to a workspace (create-user.sh --skip-workspace, or the workspace
# was removed): querying apex_workspaces blind used to return no rows, which
# left the &workspace_id substitution variable undefined and turned the export
# into `apex export-workspace -woi  -overwrite-files`. Prefer the workspace
# named after the schema -- that is what create-user.sh creates.
# SQLcl right-pads and left-pads a NUMBER to the column width, so squeeze the
# whitespace out before matching. A workspace id is 16 digits -- do not let a
# stray "0" or a row count slip through as one.
# The lookup runs as SYS, so a schema that is not in .env needs no temporary
# access to find out that it has no workspace.
WORKSPACE_ID=$(
  sql -S -name "$DB_CONN_NAME" <<SQL 2>/dev/null | tr -d ' \t\r' | grep -Ex '[0-9]{6,}' | head -n1
set heading off feedback off pagesize 0 verify off
select to_char(workspace_id)
  from (select workspace_id,
               case when workspace_name = '$USERNAME_UPPER' then 0 else 1 end as pref
          from apex_workspace_schemas
         where schema = '$USERNAME_UPPER')
 order by pref, workspace_id
 fetch first 1 row only;
exit;
SQL
)

if [ -z "$WORKSPACE_ID" ]; then
  echo "Note: schema $USERNAME_UPPER is not assigned to an APEX workspace - skipping the APEX export"
else
  echo "APEX workspace id for $USERNAME_UPPER: $WORKSPACE_ID"

  # The APEX export needs the owner. Without the inherit privileges grant, an
  # export as SYS fails with ORA-06598.
  if [ "$DISCOVERED" = true ]; then
    echo "$USERNAME_UPPER is not in .env. Using temporary access for the APEX export."
    ACCESS_BEGUN=true
    schema_access_begin "$USERNAME"
  fi

  if [ -d "$APEX_DIR" ] && [ -n "$(ls -A "$APEX_DIR" 2>/dev/null)" ]; then
    mkdir -p "${EXPORT_DIR}/apex/bkp/${USERNAME_LOWER}"
    rm -rf "${EXPORT_DIR}/apex/bkp/${USERNAME_LOWER:?}"/*
    mv "$APEX_DIR"/* "${EXPORT_DIR}/apex/bkp/${USERNAME_LOWER}/"
  fi
  mkdir -p "$APEX_DIR"

  # `apex export-workspace` and `apex export-all-applications` have no -dir
  # option, so they always write to the current directory. Do the cd in a
  # subshell so a failure here cannot leave the rest of the script running from
  # the wrong directory.
  (
    cd "$APEX_DIR"
    # The workspace id IS the security group id; set it so the APEX export APIs
    # see the workspace. Do not go via workspace_display_name -- that is a label
    # and can differ from the workspace name find_security_group_id expects.
    sql -name "$USER_DB_CONN_NAME" <<SQL
    begin
      apex_util.set_security_group_id (p_security_group_id => $WORKSPACE_ID);
    end;
    /

    apex export-workspace -woi $WORKSPACE_ID -overwrite-files
    apex export-all-applications -woi $WORKSPACE_ID -overwrite-files

    exit;
SQL
  )
fi

# ORDS export as SYS. ORDS_EXPORT_ADMIN with p_runnable_as_admin => false writes
# the same script as `rest export schema` by the owner, and import-backup runs it
# as the owner. A schema that is not REST enabled (ORA-20012) gets no file, so
# the import does not need owner access for it.
mkdir -p "$ORDS_DIR"
rm -f "$ORDS_DIR/rest_schema.sql"
ORDS_OUT=$(
  sql -S -name "$DB_CONN_NAME" <<SQL
set heading off feedback off pagesize 0 verify off linesize 32767 trimspool on
set serveroutput on size unlimited format wrapped
declare
  l_clob clob;
  l_pos  pls_integer := 1;
  l_nl   pls_integer;
  l_len  pls_integer;
begin
  l_clob := ords_metadata.ords_export_admin.export_schema(
              p_schema             => '$USERNAME_UPPER',
              p_runnable_as_admin  => false);
  dbms_output.put_line('==ORDS_EXPORT_BEGIN==');
  l_len := dbms_lob.getlength(l_clob);
  while l_pos <= l_len loop
    l_nl := dbms_lob.instr(l_clob, chr(10), l_pos);
    if l_nl = 0 then
      l_nl := l_len + 1;
    end if;
    dbms_output.put_line(dbms_lob.substr(l_clob, l_nl - l_pos, l_pos));
    l_pos := l_nl + 1;
  end loop;
  dbms_output.put_line('==ORDS_EXPORT_END==');
exception
  when others then
    if sqlcode = -20012 then
      dbms_output.put_line('==ORDS_NOT_ENABLED==');
    else
      raise;
    end if;
end;
/
exit;
SQL
)
if echo "$ORDS_OUT" | grep -q '^==ORDS_NOT_ENABLED=='; then
  echo "Note: $USERNAME_UPPER is not REST enabled - no ORDS export"
elif echo "$ORDS_OUT" | grep -q '^==ORDS_EXPORT_END=='; then
  echo "$ORDS_OUT" | sed -n '/^==ORDS_EXPORT_BEGIN==$/,/^==ORDS_EXPORT_END==$/p' | sed '1d;$d' >"$ORDS_DIR/rest_schema.sql"
else
  echo "ERROR: the ORDS export of $USERNAME_UPPER failed:" >&2
  echo "$ORDS_OUT" | grep -E 'ORA-|Error' | head -n 5 | sed 's/^/  /' >&2
  exit 1
fi
