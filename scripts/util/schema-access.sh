#!/usr/bin/env bash
# Owner access to a schema that is not in .env, without knowing its password.
#
# The backup and the import run DataPump, `apex export` and `rest export` as the
# schema owner through a saved SQLcl connection. For a schema that was made by
# hand, .env holds no password. These functions give the owner a temporary
# password, save a SQLcl connection with it, and put the old password hash back
# when the work is done.
#
#   schema_access_begin <SCHEMA>   set the temporary password, save the connection
#   schema_access_end   <SCHEMA>   put the old password hash back, delete the connection
#
# The old hash goes to ./backups/.pw-restore/<schema>.sql (mode 600) before the
# change. If the script dies without running schema_access_end, run that file as
# SYS to put the password back.
#
# Needs: DB_CONN_NAME, DB_CONN_BASE and sql. Callers use a trap for schema_access_end.

SCHEMA_ACCESS_DIR="./backups/.pw-restore"

schema_access_begin() {
  local u_upper u_lower tmp_pw state_file state
  u_upper=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  u_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  state_file="${SCHEMA_ACCESS_DIR}/${u_lower}.sql"

  mkdir -p "$SCHEMA_ACCESS_DIR"
  chmod 700 "$SCHEMA_ACCESS_DIR"

  # A restore file from an earlier run that died: restore first, so that the
  # hash we save now is the real one and not a temporary one.
  if [ -f "$state_file" ]; then
    echo "Restoring the password of $u_upper from an earlier run"
    sql -S -name "$DB_CONN_NAME" @"$state_file" >/dev/null 2>&1 || true
  fi

  state=$(
    sql -S -name "$DB_CONN_NAME" <<SQL 2>/dev/null | grep -E '^(HASH|STATUS|AUTH|DIRS)\|' || true
set heading off feedback off pagesize 0 linesize 2000 verify off
select 'HASH|' || spare4 from sys.user\$ where name = '$u_upper' and spare4 is not null;
select 'STATUS|' || account_status from dba_users where username = '$u_upper';
select 'AUTH|' || authentication_type from dba_users where username = '$u_upper';
select 'DIRS|' || count(*) from dba_tab_privs where grantee = '$u_upper' and table_name in ('DATAPUMP_EXPORT_DIR', 'DATAPUMP_IMPORT_DIR');
exit;
SQL
  )
  local hash status auth dirs
  hash=$(echo "$state" | grep '^HASH|' | head -n1 | cut -d'|' -f2- | tr -d '\r' | sed -E 's/[[:space:]]+$//')
  status=$(echo "$state" | grep '^STATUS|' | head -n1 | cut -d'|' -f2- | tr -d '\r')
  auth=$(echo "$state" | grep '^AUTH|' | head -n1 | cut -d'|' -f2- | tr -d '\r ')
  dirs=$(echo "$state" | grep '^DIRS|' | head -n1 | cut -d'|' -f2- | tr -d '\r ')
  # A schema-only account (create user ... no authentication) has no hash. It
  # gets "no authentication" back at the end.
  if [ -z "$hash" ] && [ "$auth" != "NONE" ]; then
    echo "Error: cannot read the password hash of $u_upper" >&2
    return 1
  fi

  # The restore file first, then the change.
  {
    if [ "$auth" = "NONE" ]; then
      echo "alter user \"$u_upper\" no authentication;"
    else
      echo "alter user \"$u_upper\" identified by values '$hash';"
    fi
    case "$status" in
      *LOCKED*) echo "alter user \"$u_upper\" account lock;" ;;
    esac
    # create-user.sh gives every schema access to the DataPump directories. A schema
    # that was made by hand has none, so it gets them for the work, and loses them again.
    if [ "${dirs:-0}" = "0" ]; then
      echo "revoke read, write on directory datapump_export_dir from \"$u_upper\";"
      echo "revoke read, write on directory datapump_import_dir from \"$u_upper\";"
    fi
    echo "exit"
  } >"$state_file"
  chmod 600 "$state_file"

  tmp_pw="Tmp_$(openssl rand -hex 10)#A1"
  sql -S -name "$DB_CONN_NAME" <<SQL >/dev/null
alter user "$u_upper" identified by "$tmp_pw" account unlock;
grant read, write on directory datapump_export_dir to "$u_upper";
grant read, write on directory datapump_import_dir to "$u_upper";
exit;
SQL
  sql -S "${u_lower}/\"${tmp_pw}\"@localhost:${DB_HOST_PORT:-1521}/FREEPDB1" <<SQL >/dev/null
conn -save ${DB_CONN_BASE}-${u_lower} -savepwd -replace
exit;
SQL
  echo "Temporary access to $u_upper (the password is restored at the end)"
}

schema_access_end() {
  local u_lower state_file
  u_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  state_file="${SCHEMA_ACCESS_DIR}/${u_lower}.sql"
  [ -f "$state_file" ] || return 0
  # sql exits with 0 also when a statement fails, so read the hash back and compare.
  local want now
  want=$(sed -nE "s/^alter user .* identified by values '([^']+)';\$/\1/p" "$state_file" | head -n1)
  if grep -q ' no authentication;$' "$state_file"; then want="NONE"; fi
  sql -S -name "$DB_CONN_NAME" @"$state_file" >/dev/null 2>&1 || true
  now=$(
    sql -S -name "$DB_CONN_NAME" <<SQL 2>/dev/null | tr -d '\r' | sed -E 's/[[:space:]]+$//' | grep -E '^(S:|NONE$)' | head -n1
set heading off feedback off pagesize 0 linesize 2000 verify off
select case when u.authentication_type = 'NONE' then 'NONE' else s.spare4 end
  from dba_users u join sys.user\$ s on s.name = u.username
 where u.username = '$(echo "$1" | tr '[:lower:]' '[:upper:]')';
exit;
SQL
  )
  if [ -n "$want" ] && [ "$now" = "$want" ]; then
    rm -f "$state_file"
  else
    echo "WARNING: could not restore the password of $1. Run $state_file as SYS." >&2
  fi
  sql -S /nolog <<SQL >/dev/null 2>&1 || true
connmgr delete -conn ${DB_CONN_BASE}-${u_lower}
exit;
SQL
}
