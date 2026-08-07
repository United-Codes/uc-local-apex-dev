#!/usr/bin/env bash
# desc: DataPump-export a single schema incl. its APEX workspace and apps

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/user_in_env.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name>"
  exit 1
fi
USERNAME=$1

user_in_env "$USERNAME"

USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

USER_DB_CONN_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

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
  sql -name "$USER_DB_CONN_NAME" <<'SQL' || true
    set serveroutput on size unlimited
    @./scripts/sql/drop_dp_tables.sql
    exit;
SQL
}
trap drop_dp_master_tables EXIT

# Rotate the previous dump only AFTER the new one is in hand. The old order
# (delete _bkp, then move .dmp to _bkp, then export) destroyed both copies when
# two exports failed in a row.
if [ -f "${EXPORT_DIR}/${USERNAME_LOWER}.dmp" ]; then
  rm -f "${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp"
  mv "${EXPORT_DIR}/${USERNAME_LOWER}.dmp" "${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp"
  mv -f "${EXPORT_DIR}/${USERNAME_LOWER}.log" "${EXPORT_DIR}/${USERNAME_LOWER}_bkp.log" 2>/dev/null || true
fi

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
sql -name "$USER_DB_CONN_NAME" <<SQL
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
     -version latest

    exit;
SQL

# move datapump from container to backups/export
./scripts/sync-backups-folder.sh pull

if [ ! -s "${EXPORT_DIR}/${USERNAME_LOWER}.dmp" ]; then
  echo "ERROR: no dump produced at ${EXPORT_DIR}/${USERNAME_LOWER}.dmp" >&2
  echo "       the previous dump is still at ${EXPORT_DIR}/${USERNAME_LOWER}_bkp.dmp" >&2
  exit 1
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
WORKSPACE_ID=$(
  sql -S -name "$USER_DB_CONN_NAME" <<SQL 2>/dev/null | tr -d ' \t\r' | grep -Ex '[0-9]{6,}' | head -n1
set heading off feedback off pagesize 0 verify off
select to_char(workspace_id)
  from (select workspace_id,
               case when workspace = '$USERNAME_UPPER' then 0 else 1 end as pref
          from apex_workspaces)
 order by pref, workspace_id
 fetch first 1 row only;
exit;
SQL
)

if [ -z "$WORKSPACE_ID" ]; then
  echo "Note: schema $USERNAME_UPPER is not assigned to an APEX workspace - skipping the APEX export"
else
  echo "APEX workspace id for $USERNAME_UPPER: $WORKSPACE_ID"

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

mkdir -p "$ORDS_DIR"

(
  cd "$ORDS_DIR"
  sql -name "$USER_DB_CONN_NAME" -silent >rest_schema.sql <<SQL
  rest export schema
  exit;
SQL
)
