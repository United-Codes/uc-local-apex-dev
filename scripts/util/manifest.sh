#!/usr/bin/env bash
# write_manifest <file>   write OWNER|OBJECT_TYPE|OBJECT_NAME lines for the schemas of ours
# compare_manifest <backup-manifest>   print what is missing now; return 1 if anything is missing
#
# Needs DB_CONN_NAME and sql.

MANIFEST_HEADER="# OWNER|OBJECT_TYPE|OBJECT_NAME"

write_manifest() {
  {
    echo "$MANIFEST_HEADER"
    sql -S -name "$DB_CONN_NAME" @./scripts/sql/manifest.sql 2>/dev/null |
      tr -d '\r' | sed -E 's/[[:space:]]+$//' | grep -E '^[A-Z0-9_$#]+\|[A-Z ]+\|[^|]+$' | LC_ALL=C sort -u
  } >"$1"
}

compare_manifest() {
  local before="$1" now diffs total
  now=$(mktemp "${TMPDIR:-/tmp}/manifest.XXXXXX")
  write_manifest "$now"
  if [ "$(head -n1 "$before")" = "$MANIFEST_HEADER" ]; then
    # Every object of the backup that is not in the database now.
    diffs=$(LC_ALL=C comm -23 <(grep -v '^#' "$before" | LC_ALL=C sort -u) <(grep -v '^#' "$now" | LC_ALL=C sort -u) | tr '|' ' ')
  else
    # A backup of an older release has counts: OWNER|OBJECT_TYPE|COUNT.
    diffs=$(
      grep -v '^#' "$now" | awk -F'|' '{ c[$1 "|" $2]++ } END { for (k in c) print k "|" c[k] }' |
        awk -F'|' '
          NR == FNR { want[$1 "|" $2] = $3; next }
          { have[$1 "|" $2] = $3 }
          END {
            for (k in want) {
              if (!(k in have)) printf "%s: backup %s, now 0\n", k, want[k]
              else if (have[k] + 0 < want[k] + 0) printf "%s: backup %s, now %s\n", k, want[k], have[k]
            }
          }' "$before" - | sort | tr '|' ' '
    )
  fi
  rm -f "$now"
  if [ -n "$diffs" ]; then
    total=$(echo "$diffs" | wc -l | tr -d ' ')
    echo "$diffs" | head -n 30
    [ "$total" -gt 30 ] && echo "... and $((total - 30)) more"
    return 1
  fi
  return 0
}
