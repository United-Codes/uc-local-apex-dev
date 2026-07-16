#!/usr/bin/env bash
#
# One-shot installer for uc-local-apex-dev.
#
# Runs setup.sh, pulls the container images, brings the stack up, waits for
# the database to become ready, invokes scripts/after-first-db-start.sh
# non-interactively (so the archive-logs prompt picks its default of
# "disable"), then waits for ORDS to finish its first-boot install and
# configures it. APEX and ORDS install into independent schemas, so both
# installs run in parallel on purpose.
#
# Re-running on an already-installed checkout is safe: setup.sh is skipped
# if .env already has all the keys we need, and the readiness loops return
# immediately when the stack is already up.

set -euo pipefail

CURRENT_STEP="startup"
trap 'echo "::error::install.sh failed during step: $CURRENT_STEP" >&2' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"

banner() {
  CURRENT_STEP="$1"
  echo
  echo "=== $1 ==="
}

fail_resumable() {
  echo "ERROR: $1" >&2
  echo >&2
  echo "You can safely re-run ./install.sh — it picks up where it left off." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Preflight checks
# ---------------------------------------------------------------------------
banner "Preflight checks"

MISSING=()

for cmd in sql unzip; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
  MISSING+=("curl or wget")
fi

# Detect container engine (honor a pre-set CONTAINER_CLI, else prefer docker, fall back to podman).
if [ -n "${CONTAINER_CLI:-}" ]; then
  :
elif command -v docker &>/dev/null; then
  CONTAINER_CLI="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
else
  CONTAINER_CLI=""
  MISSING+=("docker or podman")
fi

# Detect its compose command. Native '<engine> compose'; docker keeps the legacy
# 'docker-compose' v1 fallback. Podman uses ONLY 'podman compose' (no podman-compose).
if [ -z "$CONTAINER_CLI" ]; then
  :
elif $CONTAINER_CLI compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE="$CONTAINER_CLI compose"
elif [ "$CONTAINER_CLI" = "docker" ] && command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  MISSING+=("$CONTAINER_CLI compose (native compose subcommand)")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: required tools are missing:" >&2
  for cmd in "${MISSING[@]}"; do
    echo "  - $cmd" >&2
  done
  exit 1
fi

echo "Using container engine: $CONTAINER_CLI"
echo "Using compose command: $DOCKER_COMPOSE"
echo "SQLcl version:"
sql -V || true

# ---------------------------------------------------------------------------
# 2. .env handling
# ---------------------------------------------------------------------------
banner "Prepare .env"

REQUIRED_ENV_KEYS=(
  ORACLE_PASSWORD
  ORACLE_PWD
  DB_CONN_BASE
  DB_CONN_NAME
  CONTAINER_NAME
  DBSERVICENAME
  DBHOST
  DBPORT
  FORCE_SECURE
)

if [ -f .env ]; then
  echo ".env already exists — validating required keys."
  missing_keys=()
  for key in "${REQUIRED_ENV_KEYS[@]}"; do
    if ! grep -qE "^${key}=" .env; then
      missing_keys+=("$key")
    fi
  done
  if [ ${#missing_keys[@]} -gt 0 ]; then
    echo "ERROR: .env is missing required keys:" >&2
    for key in "${missing_keys[@]}"; do
      echo "  - $key" >&2
    done
    echo "Remove or fix .env and re-run ./install.sh" >&2
    exit 1
  fi
  echo ".env looks good — reusing existing passwords."
else
  echo "No .env found — running setup.sh."
  ./setup.sh
fi

# Pull in $ORACLE_PASSWORD, the sql() TTY wrapper, and (again) $DOCKER_COMPOSE.
# load_env.sh re-detects compose, which is fine — same result.
# shellcheck disable=SC1091
source ./scripts/util/load_env.sh

# ---------------------------------------------------------------------------
# 3. Pull images
# ---------------------------------------------------------------------------
banner "Pull container images"
$DOCKER_COMPOSE pull

# ---------------------------------------------------------------------------
# 4. Start the stack
# ---------------------------------------------------------------------------
banner "Start the stack"
# These bind-mount sources are gitignored (empty on a fresh checkout). Create
# them up front so the bind mounts attach cleanly on every engine — Docker used
# to auto-create them, but with explicit bind options (selinux relabel) that
# implicit behaviour is no longer guaranteed.
mkdir -p ords-config apex-images
$DOCKER_COMPOSE up -d

# ---------------------------------------------------------------------------
# 5. Wait for the database to be ready
# ---------------------------------------------------------------------------
banner "Wait for database to be ready (up to 25 minutes)"
wait_start=$SECONDS
deadline=$((SECONDS + 1500))
progress_at=$((SECONDS + 60))
db_ready=false
while (( SECONDS < deadline )); do
  # Capture the logs first, then match against the variable -- do NOT pipe
  # straight into `grep -q`. Under `set -o pipefail`, grep closes the pipe on
  # its first match (SIGPIPE to the writer) and `podman compose logs` can also
  # exit non-zero on its own, either of which makes the *pipeline* non-zero even
  # when the banner matched -- so the `if` never fired and the podman leg looped
  # until timeout despite the DB being ready. docker's compose logs exits clean,
  # which is why only podman hung. The capture + case match avoids the pipe.
  db_log=$($DOCKER_COMPOSE logs 26ai 2>&1 || true)
  case "$db_log" in
  *"DATABASE IS READY TO USE"*)
    echo "Database is ready."
    db_ready=true
    break
    ;;
  esac
  if (( SECONDS >= progress_at )); then
    echo "Still waiting for the database first boot... ($(( (SECONDS - wait_start) / 60 ))/25 min)"
    progress_at=$((SECONDS + 60))
  fi
  sleep 10
done

if [ "$db_ready" != true ]; then
  printf '%s\n' "$db_log" | tail -100 >&2 || true
  fail_resumable "database did not become ready within 25 minutes"
fi

# ---------------------------------------------------------------------------
# 6. Verify the host can reach the database via SQLcl
# ---------------------------------------------------------------------------
# Fail fast (with the real SQLcl error) when the host-side connection is
# broken -- e.g. a defunct Java/SQLcl setup or something else answering on
# port 1521. Without this check such problems would only surface as a silent
# timeout in the ORDS wait below. The short retry window covers the listener
# service-registration race right after the DB-ready banner.
banner "Verify host database connection"
deadline=$((SECONDS + 120))
db_conn_ok=false
while (( SECONDS < deadline )); do
  conn_out=$(sql -S "sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1" as SYSDBA <<'SQL' 2>&1 || true
set heading off feedback off pagesize 0
select 1 from dual;
exit
SQL
  )
  # SQLcl on Java 24+ can prepend JVM noise on stderr -- either a
  # "Picked up JAVA_TOOL_OPTIONS: ..." line (env var set) or a multi-line
  # "WARNING: restricted method ..." block (env var not set) -- and the 2>&1
  # above folds it into conn_out. Match a standalone "1" line rather than
  # squishing the whole blob, so leading noise no longer defeats the check.
  if printf '%s\n' "$conn_out" | grep -qxE '[[:space:]]*1[[:space:]]*'; then
    echo "Host database connection works."
    db_conn_ok=true
    break
  fi
  sleep 10
done

if [ "$db_conn_ok" != true ]; then
  echo "Last SQLcl output:" >&2
  printf '%s\n' "$conn_out" >&2
  fail_resumable "cannot connect to the database from this host (sys@localhost:1521/FREEPDB1).
Check that SQLcl ('sql') and its Java runtime work and that nothing else occupies port 1521."
fi

# ---------------------------------------------------------------------------
# 7. Run after-first-db-start.sh non-interactively
# ---------------------------------------------------------------------------
# Runs BEFORE the ORDS wait on purpose: it only needs the database (creates
# tablespaces, downloads + installs APEX, sets the ADMIN password), while the
# ORDS container is still busy with its own first-boot install. The two touch
# independent schemas (APEX_* vs ORDS_METADATA/ORDS_PUBLIC_USER), so running
# them in parallel absorbs slow machines where ORDS alone used to blow the
# 15-minute budget.
banner "Run after-first-db-start.sh (installs APEX, applies space optimizations)"
# Closing stdin makes the archive-logs prompt take its default (Y, disable).
# The APEX ADMIN password is no longer prompted — it reuses ORACLE_PASSWORD.
./scripts/after-first-db-start.sh </dev/null

# ---------------------------------------------------------------------------
# 8. Wait for ORDS to finish its first-boot install
# ---------------------------------------------------------------------------
banner "Wait for ORDS to be ready (up to 15 minutes)"
ords_query() {
  sql -S "sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1" as SYSDBA <<'SQL'
set heading off feedback off pagesize 0
select count(*) from dba_synonyms
 where owner = 'PUBLIC' and synonym_name = 'ORDS';
exit
SQL
}
wait_start=$SECONDS
deadline=$((SECONDS + 900))
progress_at=$((SECONDS + 60))
ords_ready=false
while (( SECONDS < deadline )); do
  count=$(ords_query 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
  if [ "$count" = "1" ]; then
    echo "ORDS is ready."
    ords_ready=true
    break
  fi
  # A dead ORDS container will never finish installing -- fail fast instead
  # of burning the whole timeout.
  running=$($CONTAINER_CLI inspect -f '{{.State.Running}}' local-26ai-ords 2>/dev/null || true)
  if [ "$running" != "true" ]; then
    $DOCKER_COMPOSE logs ords-26ai 2>/dev/null | tail -200 >&2 || true
    fail_resumable "the ORDS container (local-26ai-ords) is not running"
  fi
  if (( SECONDS >= progress_at )); then
    echo "Still waiting for the ORDS first-boot install... ($(( (SECONDS - wait_start) / 60 ))/15 min)"
    progress_at=$((SECONDS + 60))
  fi
  sleep 10
done

if [ "$ords_ready" != true ]; then
  echo "Last readiness check output:" >&2
  check_out=$(ords_query 2>&1 || true)
  printf '%s\n' "$check_out" >&2
  $DOCKER_COMPOSE logs ords-26ai 2>/dev/null | tail -200 >&2 || true
  fail_resumable "ORDS did not finish installing within 15 minutes"
fi

# ---------------------------------------------------------------------------
# 9. Configure ORDS pl/sql gateway mode = proxied
# ---------------------------------------------------------------------------
# `proxied` is the default in ORDS 26.x but older images (and explicit configs)
# may pick `direct`. Setting it explicitly keeps the APEX URL working with
# workspace-level proxy auth in all cases. The command is idempotent. It must
# stay after the ORDS wait so the first-boot installer cannot overwrite it.
banner "Configure ORDS plsql.gateway.mode = proxied"
$CONTAINER_CLI exec local-26ai-ords bash -c \
  "ords --config /etc/ords/config config --db-pool default set plsql.gateway.mode proxied"

# ---------------------------------------------------------------------------
# 10. Restart ORDS so it picks up APEX + the config change
# ---------------------------------------------------------------------------
banner "Restart ORDS to pick up APEX module"
$DOCKER_COMPOSE restart ords-26ai
# Wait for ORDS to come back so callers (and CI) can immediately use it.
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  # Capture then match (no pipe into grep) for the same pipefail reason as the
  # DB wait above: a non-zero curl/exec while ORDS is still restarting must not
  # be masked into a false positive, nor a SIGPIPE into a false negative.
  http=$($CONTAINER_CLI exec local-26ai-ords bash -c \
    "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/ords/" 2>/dev/null || true)
  case "$http" in
  200 | 30[0-9])
    echo "ORDS is back."
    break
    ;;
  esac
  sleep 5
done

# ---------------------------------------------------------------------------
# 11. Final summary
# ---------------------------------------------------------------------------
banner "Done"
cat <<EOF
The stack is up and APEX is installed.

  APEX:           https://localhost:8181/ords/
  APEX workspace: INTERNAL / ADMIN / (your ORACLE_PASSWORD from .env)
  SYS connection: sql -name "\$DB_CONN_NAME"   (after sourcing scripts/util/load_env.sh)

Next: create a workspace + schema for your app:

  ./local-26ai.sh create-user <NAME>

EOF
