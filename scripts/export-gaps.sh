#!/usr/bin/env bash
# desc: Report what a schema export does not carry and write a recovery script

set -e

# A DataPump schema export carries the objects of a schema. It does not carry
# roles, public synonyms, other users, cross-schema grants, grants on SYS
# objects or secrets such as credentials. This script reads the database as SYS
# and writes files to ./backups/export/recovery:
#
#   schemas.tsv       the schemas to back up, and whether .env has them
#   00_pre.sql        SQL that import-all runs before the imports
#   10_post.sql       SQL that import-all runs after the imports
#   manifest.tsv      every object of every schema, to check the restore
#   dirs.tsv          the custom directories and their paths
#   params.tsv        settings and components the new database needs (vector memory, DBMS_CLOUD, utPLSQL)
#   05_domains.sql    SQL domains whose DataPump DDL is broken, with corrected DDL
#   data_grant_schemas.txt  schemas with Deep Data Security data grants (import-datapump leaves out their XS objects)
#   dirfiles/         the files in these directories (up to DIR_FILES_MAX_MB each)
#   unrecoverable.txt things that nobody can restore
#   gaps-report.txt   a summary
#
# backup-all runs this script. It only reads the database.

source ./scripts/util/load_env.sh
source ./scripts/util/read_user_names.sh
source ./scripts/util/manifest.sh

OUT_DIR="./backups/export/recovery"
mkdir -p "$OUT_DIR"

ENV_LIST=""
for user in $(get_user_names); do
  # install-utplsql makes and grants the schema UTPLSQL. The recovery leaves it out.
  [ "$(echo "$user" | tr '[:lower:]' '[:upper:]')" = "UTPLSQL" ] && continue
  ENV_LIST="${ENV_LIST:+$ENV_LIST,}'$(echo "$user" | tr '[:lower:]' '[:upper:]')'"
done
ENV_LIST="${ENV_LIST:-'-'}"

# Grants that create-user.sh gives to every new schema. import-all creates the
# schemas with it, so recover.sql only needs the grants BEYOND this list. The
# list comes from the grant lines of create-user.sh, so the two cannot drift.
# Entry forms: "create table" (system privilege or role), "execute on dbms_lob"
# (object grant, "directory" removed). Lowercase.
baseline_entries() {
  local line privs obj priv
  sed -nE 's/^[[:space:]]*grant[[:space:]]+(.*)[[:space:]]+to[[:space:]]+\$\{USERNAME\};.*/\1/p' ./scripts/create-user.sh |
    tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' |
    while IFS= read -r line; do
      if [[ "$line" == *" on "* ]]; then
        privs="${line%% on *}"
        obj="${line#* on }"
        obj="${obj#directory }"
        echo "$privs" | tr ',' '\n' | sed -E 's/^ +//; s/ +$//' | while IFS= read -r priv; do
          echo "$priv on $obj"
        done
      else
        echo "$line"
      fi
    done
}

BASE_LIST=""
while IFS= read -r entry; do
  [ -n "$entry" ] && BASE_LIST="${BASE_LIST:+$BASE_LIST,}'$entry'"
done < <(baseline_entries)
if [ -z "$BASE_LIST" ]; then
  echo "Error: no baseline grants found in scripts/create-user.sh" >&2
  exit 1
fi

sql -S -name "$DB_CONN_NAME" <<SQL
define base_list = "${BASE_LIST}"
define out_dir = ${OUT_DIR}
define env_users = "${ENV_LIST}"
@./scripts/sql/export_gaps.sql
SQL

# The files in the directories: external tables, BFILEs, files for UTL_FILE. A
# rebuild deletes the volume, so copy them into the backup. import-all puts them
# back. A directory above the limit is only reported.
DIR_FILES_MAX_MB="${DIR_FILES_MAX_MB:-200}"
CONTAINER="${CONTAINER_NAME:-local-26ai}"
rm -rf "$OUT_DIR/dirfiles"
if [ -s "$OUT_DIR/dirs.tsv" ]; then
  mkdir -p "$OUT_DIR/dirfiles"
  while IFS='|' read -r name path; do
    path="${path%$'\r'}"
    path="${path%"${path##*[![:space:]]}"}"
    [ -z "$name" ] && continue
    # The single quotes are intended: $1 expands in the container.
    # shellcheck disable=SC2016
    size_mb=$($CONTAINER_CLI exec "$CONTAINER" bash -c 'test -d "$1" && du -sm "$1" | cut -f1' _ "$path" </dev/null || true)
    if [ -z "$size_mb" ]; then
      continue # the path does not exist: no files to copy. import-all creates it.
    elif [ "$size_mb" -gt "$DIR_FILES_MAX_MB" ]; then
      echo "Directory $name -> $path holds $size_mb MB. The backup copies up to $DIR_FILES_MAX_MB MB (DIR_FILES_MAX_MB in .env). Copy the files by hand" >>"$OUT_DIR/unrecoverable.txt"
    elif ! $CONTAINER_CLI exec "$CONTAINER" tar -C "$path" -cf - . >"$OUT_DIR/dirfiles/$name.tar" </dev/null; then
      rm -f "$OUT_DIR/dirfiles/$name.tar"
      echo "Directory $name -> $path: the files cannot be read. Copy them by hand" >>"$OUT_DIR/unrecoverable.txt"
    fi
  done <"$OUT_DIR/dirs.tsv"
fi

# Every object of every schema. import-all compares it after the restore.
write_manifest "$OUT_DIR/manifest.tsv"

echo ""
cat "$OUT_DIR/gaps-report.txt"
echo ""
if grep -q '[^[:space:]]' "$OUT_DIR/unrecoverable.txt"; then
  echo "Things that no backup can hold. You must enter or create them again:"
  grep -v '^[[:space:]]*$' "$OUT_DIR/unrecoverable.txt" | sed 's/^/  - /'
else
  echo "Nothing that no backup can hold."
fi
echo ""
echo "Recovery files in $OUT_DIR:"
echo "  00_pre.sql   $(grep -cvE '^(--|whenever|set |$)' "$OUT_DIR/00_pre.sql") lines (before the imports)"
echo "  10_post.sql  $(grep -cvE '^(--|whenever|set |$)' "$OUT_DIR/10_post.sql") lines (after the imports)"
echo "  schemas.tsv  $(wc -l <"$OUT_DIR/schemas.tsv" | tr -d ' ') schemas"
if [ -d "$OUT_DIR/dirfiles" ]; then
  echo "  dirfiles     files of $(find "$OUT_DIR/dirfiles" -name '*.tar' | wc -l | tr -d ' ') directories"
fi
