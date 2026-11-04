#!/usr/bin/env bash
# desc: Install an APEX patch set bundle (unzipped folder or .zip file)

set -e

source ./scripts/util/load_env.sh

usage() {
  echo "Usage: local-26ai.sh patch-apex <patch-directory|patch.zip>" >&2
  echo "Example: local-26ai.sh patch-apex ." >&2
}

if [ -z "$1" ]; then
  usage
  exit 1
fi

# local-26ai.sh changes into the repo directory, so resolve the argument
# against the directory the user started in.
TARGET="$1"
case "$TARGET" in
  /*) ;;
  *) TARGET="${ORIGINAL_PWD:-$PWD}/$TARGET" ;;
esac

TMP_DIR=""
cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

if [ -f "$TARGET" ]; then
  case "$TARGET" in
    *.zip) ;;
    *) echo "Error: $TARGET is a file but not a .zip file." >&2; exit 1 ;;
  esac
  TMP_DIR=$(mktemp -d)
  unzip -q "$TARGET" -d "$TMP_DIR"
  # A bundle unzips to a folder (for example 40040466/). Find catpatch.sql.
  CATPATCH=$(find "$TMP_DIR" -maxdepth 2 -name catpatch.sql | head -1)
  [ -n "$CATPATCH" ] || { echo "Error: no catpatch.sql in $TARGET" >&2; exit 1; }
  PATCH_DIR=$(dirname "$CATPATCH")
elif [ -d "$TARGET" ]; then
  PATCH_DIR=$(cd "$TARGET" && pwd)
else
  echo "Error: $TARGET does not exist." >&2
  exit 1
fi

if [ ! -f "$PATCH_DIR/catpatch.sql" ] || [ ! -d "$PATCH_DIR/images" ]; then
  echo "Error: $PATCH_DIR is not an APEX patch bundle (catpatch.sql or images missing)." >&2
  exit 1
fi

echo "Patch directory: $PATCH_DIR"

echo "Applying patch (catpatch.sql)"
# catpatch.sql includes its helper scripts with relative paths and writes
# catpatch.log to the current directory, so run it from the patch directory.
cd "$PATCH_DIR"
export NLS_LANG=American_America.AL32UTF8
sql -name "$DB_CONN_NAME" <<SQL
whenever sqlerror exit failure
@catpatch.sql
exit;
SQL
cd - >/dev/null

echo "Updating APEX images"
# Copy over the existing files. Do not clear the directory: it is a live
# bind-mount source for the ORDS container.
mkdir -p ./apex-images
cp -R "$PATCH_DIR/images/." ./apex-images/

echo "Patch installed. If the APEX version in your browser looks old, do a hard refresh."
