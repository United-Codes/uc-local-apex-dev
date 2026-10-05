#!/usr/bin/env bash
# desc: Raise open_cursors so large APEX imports do not fail with ORA-01000

set -e

# The Oracle Free image ships FREEPDB1 with open_cursors=300, and that is too
# low for the APEXlang importer in SQLcl ("apex import -input <dir>").
#
# The importer opens its cursors in ONE session, and the count scales with the
# size of the application. Measured on a 53-page application (237 regions, 262
# items, 105 processes) against 26ai Free 23.26.3.0.0 with APEX 26.1.2, while a
# second session sampled "opened cursors current" every 50 ms:
#
#   run 1: OK  peak=297      run 3: OK  peak=298
#   run 2: OK  peak=295      run 4: OK  peak=298
#
# That leaves 2 to 5 cursors of headroom below the limit of 300. Recursive
# dictionary lookups and the session cursor cache use the rest, so the same
# import fails at random with:
#
#   Type: PLSQL_ERROR
#   Error: ORA-01000: maximum open cursors for session exceeded
#   ORA-00604: Error occurred at recursive SQL level 3.
#
# This looks like an application failure, but it is not. The application is
# correct and the failure moves between runs. A larger application crosses the
# limit permanently.
#
# open_cursors is a per-session ceiling, not an allocation. A session pays only
# for the cursors it opens, so 1000 costs nothing on an idle system. 1000 is
# also the value the Oracle documentation uses as a starting point for an
# application server.
#
# The parameter is PDB-modifiable and ISSYS_MODIFIABLE=IMMEDIATE, so no restart
# is necessary. scope=both makes the value survive a restart.

TARGET_OPEN_CURSORS="${1:-${OPEN_CURSORS:-1000}}"

if ! [[ "$TARGET_OPEN_CURSORS" =~ ^[0-9]+$ ]] \
  || [ "$TARGET_OPEN_CURSORS" -lt 300 ] \
  || [ "$TARGET_OPEN_CURSORS" -gt 65535 ]; then
  echo "ERROR: open_cursors must be a whole number between 300 and 65535, got '$TARGET_OPEN_CURSORS'" >&2
  echo "Usage: $0 [value]   (default 1000, or \$OPEN_CURSORS)" >&2
  exit 1
fi

source ./scripts/util/load_env.sh

# Tag the value instead of reading a bare number. SQLcl on Java 24+ can prepend
# JVM noise ("Picked up JAVA_TOOL_OPTIONS: ...", "WARNING: restricted method
# ...") on stderr, and a bare number is not safe to grep out of that.
read_open_cursors() {
  sql -S -name "$DB_CONN_NAME" <<'SQL' 2>/dev/null | grep -oE 'UC_OPEN_CURSORS=[0-9]+' | head -1 | cut -d= -f2
set heading off feedback off pagesize 0
select 'UC_OPEN_CURSORS=' || value from v$parameter where name = 'open_cursors';
exit
SQL
}

current=$(read_open_cursors || true)

if [ -z "$current" ]; then
  echo "ERROR: cannot read open_cursors from the database (connection '$DB_CONN_NAME')." >&2
  echo "Make sure that the database runs and that the saved SQLcl connection exists." >&2
  exit 1
fi

echo "Current open_cursors: $current (target $TARGET_OPEN_CURSORS)"

# Only ever raise the value. A user who set a higher ceiling keeps it, and a
# re-run of install.sh changes nothing.
if [ "$current" -ge "$TARGET_OPEN_CURSORS" ]; then
  echo "open_cursors is already $current — no change."
  exit 0
fi

sql -name "$DB_CONN_NAME" <<SQL
alter system set open_cursors = $TARGET_OPEN_CURSORS scope = both;
SQL

new=$(read_open_cursors || true)

if [ "$new" != "$TARGET_OPEN_CURSORS" ]; then
  echo "ERROR: open_cursors is '$new' after the change, expected '$TARGET_OPEN_CURSORS'." >&2
  exit 1
fi

echo "Raised open_cursors from $current to $new. The change is immediate — no restart is necessary."
