#!/usr/bin/env bash
# desc: Create hand-made objects that a schema export does not carry, and compare them after a restore

set -e

# Test of backup-all and import-all. The fixtures are users, grants, synonyms,
# jobs, credentials and more that a developer creates by hand.
#
#   test-backup-fixtures.sh create          create the fixtures (needs SYS)
#   test-backup-fixtures.sh probe <file>    write the state of every fixture to <file>
#   test-backup-fixtures.sh compare <a> <b> show what differs between two probe files
#   test-backup-fixtures.sh drop            drop the fixtures
#
# The flow is: create, probe before.txt, rebuild, probe after.txt, compare.
# Run it ONLY on a test database. `create` makes users, a tablespace and an APEX
# workspace. Never run it on a database that you use.

source ./scripts/util/load_env.sh
source ./scripts/util/read_user_names.sh

CONTAINER="${CONTAINER_NAME:-local-26ai}"

cmd="${1:-}"
case "$cmd" in
  create)
    # One schema from .env gets settings that create-user.sh does not give.
    env_user=$(get_user_names | awk '{print $1; exit}' | tr '[:lower:]' '[:upper:]')
    if [ -z "$env_user" ]; then
      echo "Error: .env has no schema. Create one with create-user first." >&2
      exit 1
    fi
    echo "Creating the fixtures on $DB_CONN_NAME. Statements that fail show an error, and the run continues."
    # Files for the external table and the BFILE.
    # shellcheck disable=SC2016
    $CONTAINER_CLI exec "$CONTAINER" bash -c '
      mkdir -p /opt/oracle/oradata/fx_dir /opt/oracle/oradata/fx_dir2
      printf "1,alpha\n2,beta\n" > /opt/oracle/oradata/fx_dir/fx.csv
      printf "hello bfile" > /opt/oracle/oradata/fx_dir2/fx.txt'
    sql -name "$DB_CONN_NAME" <<SQL
define env_user = $env_user
@./scripts/sql/test_fixtures_create.sql
SQL
    # Some objects only the owner can create. FXA has a fixed password.
    sql "fxa/\"Fx_Pw_12345a#\"@localhost:${DB_HOST_PORT:-1521}/FREEPDB1" @./scripts/sql/test_fixtures_create_fxa.sql
    # SQL Firewall: FXB runs SQL while the capture is on, then SYS makes the allow list.
    sql -S "fxb/\"Fx_Pw_12345b#\"@localhost:${DB_HOST_PORT:-1521}/FREEPDB1" <<'SQL'
select count(*) from t;
exit
SQL
    sql -S -name "$DB_CONN_NAME" <<'SQL'
begin
  sys.dbms_sql_firewall.stop_capture('FXB');
  sys.dbms_sql_firewall.generate_allow_list('FXB');
end;
/
exit
SQL
    ;;
  probe)
    out="${2:?Usage: $0 probe <file>}"
    sql -S -name "$DB_CONN_NAME" @./scripts/sql/test_fixtures_probe.sql 2>&1 | grep -E '^[a-z0-9_.]+\|' | sort > "$out"
    echo "wrote $(wc -l < "$out") probe lines to $out"
    ;;
  compare)
    a="${2:?Usage: $0 compare <before> <after>}"
    b="${3:?Usage: $0 compare <before> <after>}"
    if diff <(cat "$a") <(cat "$b") >/tmp/fixtures.diff; then
      echo "All probes are identical."
    else
      echo "Probes that differ (< before, > after):"
      cat /tmp/fixtures.diff
      rm -f /tmp/fixtures.diff
      exit 1
    fi
    rm -f /tmp/fixtures.diff
    ;;
  drop)
    env_user=$(get_user_names | awk '{print $1; exit}' | tr '[:lower:]' '[:upper:]')
    sql -name "$DB_CONN_NAME" <<SQL
define env_user = ${env_user:-NONE}
@./scripts/sql/test_fixtures_drop.sql
SQL
    $CONTAINER_CLI exec "$CONTAINER" rm -rf /opt/oracle/oradata/fx_dir /opt/oracle/oradata/fx_dir2 || true
    ;;
  *)
    echo "Usage: $0 create | probe <file> | compare <before> <after> | drop"
    exit 1
    ;;
esac
