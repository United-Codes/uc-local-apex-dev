#!/usr/bin/env bash
#
# One-shot installer for uc-local-apex-dev.
#
# Runs setup.sh, pulls the container images, brings the stack up, waits for
# the database and ORDS to become ready, then invokes
# scripts/after-first-db-start.sh non-interactively (so the archive-logs
# prompt picks its default of "disable").
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
# Rootless podman boots the DB noticeably slower than docker -- first-boot has
# been observed at ~28 min under podman vs ~15 min under docker for the same
# image -- so give podman a wider ceiling. docker keeps the tighter 25 min so a
# real docker-side regression still fails fast instead of hiding for 40 minutes.
if [ "$CONTAINER_CLI" = "podman" ]; then
  db_wait_secs=2400 # 40 minutes
else
  db_wait_secs=1500 # 25 minutes
fi
banner "Wait for database to be ready (up to $((db_wait_secs / 60)) minutes)"
deadline=$((SECONDS + db_wait_secs))
db_ready=false
while (( SECONDS < deadline )); do
  if $DOCKER_COMPOSE logs 26ai 2>&1 | grep -q "DATABASE IS READY TO USE!"; then
    echo "Database is ready."
    db_ready=true
    break
  fi
  sleep 10
done

if [ "$db_ready" != true ]; then
  echo "ERROR: database did not become ready within $((db_wait_secs / 60)) minutes" >&2
  $DOCKER_COMPOSE logs 26ai | tail -100 >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 6. Wait for ORDS to finish its first-boot install
# ---------------------------------------------------------------------------
banner "Wait for ORDS to be ready (up to 15 minutes)"
deadline=$((SECONDS + 900))
ords_ready=false
while (( SECONDS < deadline )); do
  count=$(sql -S "sys/${ORACLE_PASSWORD}@localhost:1521/FREEPDB1" as SYSDBA <<'SQL' 2>/dev/null | tr -d '[:space:]' || true
set heading off feedback off pagesize 0
select count(*) from dba_synonyms
 where owner = 'PUBLIC' and synonym_name = 'ORDS';
exit
SQL
  )
  if [ "$count" = "1" ]; then
    echo "ORDS is ready."
    ords_ready=true
    break
  fi
  sleep 10
done

if [ "$ords_ready" != true ]; then
  echo "ERROR: ORDS did not finish installing within 15 minutes" >&2
  $DOCKER_COMPOSE logs ords-26ai | tail -100 >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 7. Configure ORDS pl/sql gateway mode = proxied
# ---------------------------------------------------------------------------
# `proxied` is the default in ORDS 26.x but older images (and explicit configs)
# may pick `direct`. Setting it explicitly keeps the APEX URL working with
# workspace-level proxy auth in all cases. The command is idempotent.
banner "Configure ORDS plsql.gateway.mode = proxied"
$CONTAINER_CLI exec local-26ai-ords bash -c \
  "ords --config /etc/ords/config config --db-pool default set plsql.gateway.mode proxied"

# ---------------------------------------------------------------------------
# 8. Run after-first-db-start.sh non-interactively
# ---------------------------------------------------------------------------
banner "Run after-first-db-start.sh (installs APEX, applies space optimizations)"
# Closing stdin makes the archive-logs prompt take its default (Y, disable).
# The APEX ADMIN password is no longer prompted — it reuses ORACLE_PASSWORD.
./scripts/after-first-db-start.sh </dev/null

# ---------------------------------------------------------------------------
# 9. Restart ORDS so it picks up APEX + the config change
# ---------------------------------------------------------------------------
banner "Restart ORDS to pick up APEX module"
$DOCKER_COMPOSE restart ords-26ai
# Wait for ORDS to come back so callers (and CI) can immediately use it.
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  if $CONTAINER_CLI exec local-26ai-ords bash -c \
       "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/ords/" \
       2>/dev/null | grep -qE '^(200|30[0-9])$'; then
    echo "ORDS is back."
    break
  fi
  sleep 5
done

# ---------------------------------------------------------------------------
# 10. Final summary
# ---------------------------------------------------------------------------
banner "Done"
cat <<EOF
The stack is up and APEX is installed.

  APEX:           https://localhost:8443/ords/
  APEX workspace: INTERNAL / ADMIN / (your ORACLE_PASSWORD from .env)
  SYS connection: sql -name "\$DB_CONN_NAME"   (after sourcing scripts/util/load_env.sh)

Next: create a workspace + schema for your app:

  ./scripts/create-user.sh <NAME>

EOF
