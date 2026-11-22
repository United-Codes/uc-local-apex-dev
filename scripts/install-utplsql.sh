#!/usr/bin/env bash
# desc: Install or upgrade utPLSQL in the schema UTPLSQL (optional version, --force)

set -e

source ./scripts/util/load_env.sh
source ./scripts/util/generate_password.sh

UT_OWNER=UTPLSQL
UT_TABLESPACE=tbs_utplsql
UT_TBS_MAXSIZE="${USER_TBS_MAXSIZE:-2G}"
ENV_VAR=${UT_OWNER}_USER_PASSWORD
REPO=utPLSQL/utPLSQL

usage() {
  echo "Usage: $0 [version] [--force]" >&2
  echo "Example: $0           (install or upgrade to the latest release)" >&2
  echo "Example: $0 3.2.2     (install a specific release)" >&2
  echo "Option --force installs again when the version is already installed." >&2
}

REQUESTED=""
FORCE=false
while [ $# -gt 0 ]; do
  case $1 in
  --force) FORCE=true ;;
  -h | --help) usage; exit 0 ;;
  -*) echo "Error: unknown option '$1'" >&2; usage; exit 1 ;;
  *) REQUESTED=$1 ;;
  esac
  shift
done

# "v.3.2.3", "v3.1.14.4197" and "3.2.3" all become "3.2.3" (first three parts).
normalize_version() {
  printf '%s' "$1" | sed 's/^[vV]\.*//' | cut -d. -f1-3
}

# Run SQL as SYS in the PDB. Print only the lines that start with the marker.
sql_value() {
  sql -S -name "$DB_CONN_NAME" <<SQL | sed -n 's/^RESULT=//p' | tr -d '\r' | tail -1
set heading off feedback off pagesize 0 verify off serveroutput on
$1
exit
SQL
}

# Release tags are not consistent (v.3.2.3, v3.2.2, v3.2.01), so ask GitHub.
if [ -n "$REQUESTED" ]; then
  BARE=${REQUESTED#v}
  BARE=${BARE#.}
  RELEASE_JSON=""
  for tag in "$REQUESTED" "v$BARE" "v.$BARE"; do
    if RELEASE_JSON=$(curl -fsS "https://api.github.com/repos/$REPO/releases/tags/$tag" 2>/dev/null); then
      break
    fi
    RELEASE_JSON=""
  done
  [ -n "$RELEASE_JSON" ] || { echo "Error: no utPLSQL release found for '$REQUESTED'." >&2; exit 1; }
else
  RELEASE_JSON=$(curl -fsS "https://api.github.com/repos/$REPO/releases/latest") ||
    { echo "Error: cannot read the latest release from GitHub." >&2; exit 1; }
fi

TAG=$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
asset_url() {
  printf '%s' "$RELEASE_JSON" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | grep -E "/$1\$" | head -1 || true
}
ZIP_URL=$(asset_url utPLSQL.zip)
[ -n "$ZIP_URL" ] || { echo "Error: release $TAG has no utPLSQL.zip." >&2; exit 1; }
TARGET_VERSION=$(normalize_version "$TAG")
echo "Release: $TAG"

# Read the installed version from the constant GC_VERSION in the UT_UTILS
# specification. SYS cannot call UT_RUNNER.VERSION (ORA-06598, invoker rights).
read_installed_version() {
  sql_value "
declare
  v varchar2(100);
begin
  for r in (select text from dba_source
             where owner = '$UT_OWNER' and name = 'UT_UTILS' and type = 'PACKAGE'
               and regexp_like(text, 'gc_version\\s+constant', 'i')) loop
    v := regexp_substr(r.text, '''([^'']+)''', 1, 1, null, 1);
  end loop;
  dbms_output.put_line('RESULT=' || nvl(v, 'NONE'));
end;
/"
}

INSTALLED=$(read_installed_version)
[ -n "$INSTALLED" ] || { echo "Error: cannot read the installed version." >&2; exit 1; }

if [ "$INSTALLED" = "NONE" ]; then
  echo "utPLSQL is not installed. Installing $TARGET_VERSION."
  MODE=install
else
  echo "Installed version: $INSTALLED"
  if [ "$(normalize_version "$INSTALLED")" = "$TARGET_VERSION" ] && [ "$FORCE" != true ]; then
    echo "utPLSQL $TARGET_VERSION is already installed. Use --force to install it again."
    exit 0
  fi
  echo "Upgrading to $TARGET_VERSION. The upgrade drops the schema $UT_OWNER and creates it again."
  MODE=upgrade
fi

# Password: reuse the one in .env, or create one and save it.
if [ -z "${!ENV_VAR:-}" ]; then
  UT_PASSWORD=$(generate_password)
  echo "${ENV_VAR}=\"$UT_PASSWORD\"" >>.env
  echo "Saved ${ENV_VAR} in .env"
else
  UT_PASSWORD=${!ENV_VAR}
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Downloading $ZIP_URL"
curl -fsSL -o "$WORK_DIR/utPLSQL.zip" "$ZIP_URL"

# Verify the checksum. Newer releases have .sha256 and older releases have .md5.
verified=false
for algo in sha256 md5; do
  SUM_URL=$(asset_url "utPLSQL.zip.$algo")
  [ -n "$SUM_URL" ] || continue
  if [ "$algo" = sha256 ]; then
    EXPECTED=$(curl -fsSL "$SUM_URL" | grep -Eo '[0-9a-fA-F]{64}' | head -1 | tr 'A-F' 'a-f')
    ACTUAL=$(shasum -a 256 "$WORK_DIR/utPLSQL.zip" | cut -d' ' -f1)
  else
    EXPECTED=$(curl -fsSL "$SUM_URL" | grep -Eo '[0-9a-fA-F]{32}' | head -1 | tr 'A-F' 'a-f')
    if command -v md5sum >/dev/null 2>&1; then
      ACTUAL=$(md5sum "$WORK_DIR/utPLSQL.zip" | cut -d' ' -f1)
    else
      ACTUAL=$(md5 -q "$WORK_DIR/utPLSQL.zip")
    fi
  fi
  if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Error: the $algo checksum of the download does not match." >&2
    exit 1
  fi
  echo "Checksum ($algo) verified."
  verified=true
  break
done
[ "$verified" = true ] || echo "Warning: the release has no checksum file. The download is not verified."

unzip -q "$WORK_DIR/utPLSQL.zip" -d "$WORK_DIR/unzipped"
SRC_DIR="$WORK_DIR/unzipped/utPLSQL/source"
[ -f "$SRC_DIR/install_headless_with_trigger.sql" ] ||
  { echo "Error: install_headless_with_trigger.sql is missing in the download." >&2; exit 1; }

# Prepare the database. The tablespace stays on an upgrade.
if [ "$MODE" = upgrade ]; then
  PREP_DROP="
  execute immediate 'drop user $UT_OWNER cascade';
  for s in (select owner, synonym_name from dba_synonyms
             where owner = 'PUBLIC' and table_owner = '$UT_OWNER') loop
    execute immediate 'drop public synonym \"' || s.synonym_name || '\"';
  end loop;"
else
  PREP_DROP=""
fi

echo "Preparing the database"
sql -name "$DB_CONN_NAME" <<SQL
whenever sqlerror exit failure
declare
  n number;
begin
  select count(*) into n from dba_tablespaces where tablespace_name = upper('$UT_TABLESPACE');
  if n = 0 then
    execute immediate 'create tablespace $UT_TABLESPACE datafile ''$UT_TABLESPACE.dat'' size 10M reuse autoextend on next 2M maxsize $UT_TBS_MAXSIZE';
  end if;
$PREP_DROP
end;
/
exit
SQL

# The install scripts use relative includes and write install.log to the
# current directory, so run them from the source directory.
echo "Installing utPLSQL with the DDL trigger"
cd "$SRC_DIR"
sql -name "$DB_CONN_NAME" <<SQL
whenever sqlerror exit failure
@install_headless_with_trigger.sql $UT_OWNER "$UT_PASSWORD" $UT_TABLESPACE
SQL
cd - >/dev/null

echo "Checking the installation"
sql -name "$DB_CONN_NAME" <<SQL
set pagesize 50 linesize 160 feedback off
select count(*) as invalid_objects from dba_objects
 where owner = '$UT_OWNER' and status <> 'VALID';
select trigger_name, status from dba_triggers where owner = '$UT_OWNER';
exit
SQL

echo "Installed version: $(read_installed_version)"
echo "utPLSQL $TARGET_VERSION is installed in the schema $UT_OWNER."
