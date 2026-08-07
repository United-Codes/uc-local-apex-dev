#!/usr/bin/env bash
# desc: Find and repair a data dictionary left behind by a 26ai container image RU swap
#
# ============================================================================
# WHY THIS SCRIPT EXISTS
# ============================================================================
#
# The Oracle Free 26ai image ships a PREBUILT database. When the container
# starts on an empty volume it copies that prebuilt database into
# /opt/oracle/oradata. When it starts on a volume that already holds a
# database, it only relinks the configuration files and opens what is there.
# It never upgrades anything -- there is no upgrade code in the entrypoint at
# all (grep for "upgrad" in /opt/oracle/*.sh returns nothing).
#
# So if you keep your oradata volume and change the image tag from, for
# example, 23.26.0.0 to 23.26.2.0, you get:
#
#   * 23.26.2 binaries
#   * a 23.26.0 data dictionary
#
# The container reports healthy. There is NO error. Every table, index,
# package and row stays valid. The only trace is dba_registry_history, which
# keeps the RU that created the volume.
#
# What you actually lose is every dictionary object that a skipped RU added.
# Measured on a real 23.26.0 -> 23.26.2 swap:
#
#   * All 9 assertion views (DBA_ASSERTIONS and relatives), added in 23.26.1.
#     The 6 ASSERT*$ base tables were already present, so `grant create
#     assertion` even succeeds -- the privilege is compiled into the binary --
#     but `select * from dba_assertions` raises ORA-00942.
#   * All 9 Deep Data Security / end-user-context views, added in 23.26.2.
#   * The in-database JVM. Any Java call raises
#       ORA-29548: ... could not find classes.bin version that matches
#                  executable version
#     while dba_registry still reports JAVAVM VALID. The status flag is stale.
#     Test it with: select dbms_java.longname('TEST') from dual;
#
# ============================================================================
# WHY THE SUPPORTED TOOLS DO NOT HELP
# ============================================================================
#
# Both official paths were tried on a real reproduction and both refuse:
#
#   datapatch -verbose
#     Prints the mismatch it found:
#       Binary registry: 23.26.2.0.0 Release_Update 260428181725: Installed
#       PDB CDB$ROOT:    Applied 23.26.0.0.0 Release_Update 260428181725
#     then concludes "No release update patches need to be installed". It
#     matches on the RU patch ID, which is identical in both, and ignores the
#     differing version string. The Free image carries no OPatch inventory
#     entry ("There are no Interim patches installed in this Oracle Home"), so
#     there is nothing for it to act on.
#
#     WARNING: datapatch is worse than useless here. Its "bootstrapping
#     registry" step REWRITES dba_registry_history to the new RU while applying
#     zero dictionary changes. That destroys the only evidence of the problem.
#     Always record dba_registry_history BEFORE running datapatch. This script
#     prints it first for that reason.
#
#   catctl.pl catupgrd.sql  (and AutoUpgrade, which uses the same check)
#     Exits in about 2 seconds with:
#       PDB$SEED Open Mode = [MIGRATE] NO UPGRADE WILL BE PERFORMED
#       Container Database is already at current version.
#       ** Must upgrade either a CDB$ROOT or a Pdb **
#     It compares "23.0.0.0.0" against "23.0.0.0.0". The RU digits (26.0 versus
#     26.2) never enter the comparison.
#
# ============================================================================
# WHAT DOES WORK -- AND THE ORDER MATTERS
# ============================================================================
#
# Oracle ships the pieces; nothing drives them. Each feature added by an RU has
# up to three parts, and running only some of them leaves the database worse
# than before:
#
#   1. backport_files/bug_<n>_apply.sql
#      Creates or alters the base tables, inserts the SYSTEM_PRIVILEGE_MAP /
#      TABLE_PRIVILEGE_MAP / STMT_AUDIT_OPTION_MAP rows, and records itself in
#      sys.registry$backports. Its own header says "It is run by datapatch to
#      apply the patch to existing databases" -- which is exactly the thing
#      that does not happen here. SQL_STARTUP_MODE is NORMAL, so no UPGRADE
#      mode is needed.
#
#   2. The view script -- catassertion.sql, rxsviews.sql, and so on.
#      Pure CREATE OR REPLACE VIEW plus public synonyms, so it is idempotent.
#
#   3. The matching prvt*.plb package bodies.
#      THIS IS THE STEP THAT IS EASY TO MISS. Step 1 changes a base table's
#      column list, but the package bodies still in the dictionary were
#      compiled by the OLD RU and still insert the old column count. Skipping
#      step 3 leaves SYS.XS_DATA_SECURITY_INT and SYS.XS_SECURITY_CLASS_INT
#      INVALID with ORA-00947: not enough values, and marks the whole CATPROC
#      component INVALID. This script therefore runs a heal loop: recompile,
#      look for invalid SYS package bodies, reload the .plb that defines each
#      one, recompile again.
#
#   4. The JVM, separately: javavm/install/update_javavm_db.sql.
#      initjvm.sql refuses with ORA-29539 (Java system classes already
#      installed), so it is the wrong tool. update_javavm_db.sql is the
#      patch-time script and it works.
#
#   5. dbms_registry_sys.validate_components in every container, to clear the
#      stale JAVAVM VALID/INVALID flag once the JVM actually works.
#
# Everything is driven through catcon.pl so it reaches CDB$ROOT, PDB$SEED and
# every PDB. --force_pdb_mode "READ WRITE" is required to touch PDB$SEED.
# Note: --force_pdb_mode and -m are mutually exclusive; passing both fails with
# "at most one of --pdb_seed_mode and --force_open_mode may be specified".
#
# ============================================================================
# THE LIMIT OF THIS APPROACH -- READ THIS BEFORE TRUSTING IT
# ============================================================================
#
# There are 383 *_apply.sql scripts in backport_files and NOTHING tells you
# which ones correspond to the RUs you skipped. This script works from a
# curated list of view names published in the 26ai "Changes in This Release"
# reference, resolves each missing view back to its defining script, and repairs
# those. That covers the dictionary surface you can name. It CANNOT prove that
# nothing else is missing -- fixed tables, PL/SQL behaviour changes and
# optimizer metadata are not visible this way.
#
# Treat this as a rescue tool for an environment you cannot rebuild. The
# reliable answer is: do not carry an oradata volume across RU versions.
# Create a fresh volume on the new image and move data with Data Pump.
#
# ============================================================================
# AFTER RUNNING THIS ON A REAL DATABASE: CHECK YOUR OWN SCHEMAS
# ============================================================================
#
# Reloading catalog scripts invalidates dependents, and the utlrp pass then
# recompiles them in parallel. Package bodies that call a SQL MACRO can fail
# that parallel recompile with a misleading error:
#
#   PL/SQL: ORA-62565: The SQL Macro method failed with error(s).
#   PLS-00201: identifier 'SOME_MACRO_FN' must be declared
#
# even though the macro function itself is present and VALID. It is a
# recompile-ordering artifact, not damage. A serial, single-object recompile
# fixes it every time:
#
#   alter package "OWNER"."PKG_NAME" compile body;
#
# Observed on a real dev database: 62 invalid objects before, 22 after (the
# repair fixed 41, including 7 invalid SYS audit objects), with 3 user package
# bodies newly invalid purely from this effect -- all 3 compiled cleanly on a
# single retry. So: compare the invalid-object list before and after, and
# serially recompile anything that newly appears. This script deliberately does
# NOT auto-recompile application schemas; that is your code, not the dictionary.
#
# ============================================================================
# HOW TO VALIDATE THAT THIS STILL WORKS ON A FUTURE RU
# ============================================================================
#
# The regression test that produced all of the above is reproducible on any
# throwaway Docker host with about 25 GB free:
#
#   1. docker volume create ru-test
#      docker run -d --name ru-test -e ORACLE_PWD=... \
#        -v ru-test:/opt/oracle/oradata --shm-size=2g \
#        container-registry.oracle.com/database/free:<OLD_RU>
#      Wait for "DATABASE IS READY TO USE" in the logs.
#
#   2. Create some objects and data, and record a fingerprint
#      (row counts and sums) so you can prove nothing was lost.
#
#   3. docker stop -t 300 ru-test && docker rm ru-test
#      Start the SAME volume on free:<NEW_RU>. Both tags must use the same
#      ORACLE_HOME path or the relinked config files break -- check with
#      `docker run --rm --entrypoint bash <image> -c 'ls -d /opt/oracle/product/*/dbhomeFree'`.
#
#   4. Run this script with --check. It must report the RU mismatch, the
#      missing views and the broken JVM. If it reports a clean database, either
#      Oracle fixed the image or the curated view list needs the new RU's
#      views added (see NEW_VIEWS_* below).
#
#   5. Run with --repair, then --check again. Everything must come back clean
#      and the data fingerprint must be unchanged.
#
#   6. As a control, start a FRESH volume on free:<NEW_RU> and run --check
#      against it. It must be clean. That is what proves a finding is caused by
#      the swap and not by the image itself.
#
# When a new RU ships, add its new view names to NEW_VIEWS_<RU> from
# https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/changes-this-release-oracle-database-reference.html
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Curated dictionary views by the RU that introduced them.
#
# Source: 26ai "Changes in This Release for Oracle Database Reference".
# These are the probes. A missing view is resolved back to the script that
# defines it, so the list does not need to be exhaustive -- it needs to have at
# least one representative view per feature an RU added.
# ---------------------------------------------------------------------------
NEW_VIEWS_23_26_1="
DBA_ASSERTIONS ALL_ASSERTIONS USER_ASSERTIONS
DBA_ASSERTION_DEPENDENCIES ALL_ASSERTION_DEPENDENCIES USER_ASSERTION_DEPENDENCIES
DBA_ASSERTION_LOCK_MATRIX ALL_ASSERTION_LOCK_MATRIX USER_ASSERTION_LOCK_MATRIX
DBA_PG_COMMENTS ALL_PG_COMMENTS USER_PG_COMMENTS
"

NEW_VIEWS_23_26_2="
DBA_APPLICATION_IDENTITIES
DBA_DATA_GRANTS ALL_DATA_GRANTS USER_DATA_GRANTS
DBA_DATA_ROLES DBA_DATA_ROLE_GRANTS
DBA_END_USER_SECURITY_CONTEXTS
DBA_END_USER_SECURITY_CONTEXT_ATTRIBUTES
DBA_END_USER_SECURITY_CONTEXT_DATA_ROLES
"

NEW_VIEWS_23_26_3="
DBA_AVTUNE_PENDING_REMOVAL_TABLES ALL_AVTUNE_PENDING_REMOVAL_TABLES
USER_AVTUNE_PENDING_REMOVAL_TABLES
DBA_HIST_CLIENT_REQUEST_HISTOGRAM
DBA_HIST_SERVICE_DRAIN_TIMEOUT_ADVICE
DBA_HIST_VECTOR_INDEX
DBA_REQUIRED_PARENT_DATA_PRIVILEGES ALL_REQUIRED_PARENT_DATA_PRIVILEGES
USER_REQUIRED_PARENT_DATA_PRIVILEGES
"

ALL_PROBE_VIEWS="$NEW_VIEWS_23_26_1 $NEW_VIEWS_23_26_2 $NEW_VIEWS_23_26_3"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
MODE="check"
CONTAINER=""
SYS_PWD=""
EXTRA_VIEWS=""
ASSUME_YES="false"

usage() {
  cat <<'USAGE'
Usage: scripts/repair-ru-dictionary.sh [options]

  --check                Diagnose only. Read-only. This is the default.
  --summary              Read-only, machine-readable "key=value" lines only.
                         Built for CI: assert with `grep -qx 'jvm_ok=yes'` and
                         friends, the same style as .github/fixtures/upgrade.
  --repair               Apply the repairs. Needs the SYS password.
  --container NAME       Database container. Defaults to $CONTAINER_NAME from .env.
  --password PW          SYS password. Defaults to $ORACLE_PWD from .env.
                         Only needed for --repair (catcon.pl cannot use OS auth
                         reliably; plain sqlplus calls use "/ as sysdba").
  --views "A,B,C"        Extra view names to probe, on top of the curated list.
  -y, --yes              Do not ask for confirmation before repairing.
  -h, --help             This text.

Examples:
  scripts/repair-ru-dictionary.sh --check
  scripts/repair-ru-dictionary.sh --repair
  scripts/repair-ru-dictionary.sh --check --container ru-test --password Welcome_1234
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --summary)   MODE="summary" ;;
    --repair)    MODE="repair" ;;
    --container) CONTAINER="${2:-}"; shift ;;
    --password)  SYS_PWD="${2:-}"; shift ;;
    --views)     EXTRA_VIEWS="$(echo "${2:-}" | tr ',' ' ')"; shift ;;
    -y|--yes)    ASSUME_YES="true" ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

ALL_PROBE_VIEWS="$ALL_PROBE_VIEWS $EXTRA_VIEWS"

# ---------------------------------------------------------------------------
# Environment. .env is optional so the script can run against a throwaway test
# container on a host that has no checkout of this project.
# ---------------------------------------------------------------------------
CLI="${CONTAINER_CLI:-}"
if [ -f .env ] && [ -z "$CONTAINER" -o -z "$SYS_PWD" ]; then
  # load_env.sh echoes "loaded .env file"; in --summary mode stdout must contain
  # nothing but key=value lines, so swallow it there.
  if [ "$MODE" = "summary" ]; then
    # shellcheck source=scripts/util/load_env.sh
    source ./scripts/util/load_env.sh >/dev/null
  else
    # shellcheck source=scripts/util/load_env.sh
    source ./scripts/util/load_env.sh
  fi
  CLI="${CONTAINER_CLI:-docker}"
fi
[ -z "$CLI" ] && CLI="$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)"

[ -z "$CONTAINER" ] && CONTAINER="${CONTAINER_NAME:-}"
[ -z "$SYS_PWD" ] && SYS_PWD="${ORACLE_PWD:-}"

if [ -z "$CONTAINER" ]; then
  echo "Error: no container name. Pass --container NAME or set CONTAINER_NAME in .env." >&2
  exit 1
fi
if ! $CLI ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Error: container '$CONTAINER' is not running." >&2
  exit 1
fi
if [ "$MODE" = "repair" ] && [ -z "$SYS_PWD" ]; then
  echo "Error: --repair needs the SYS password. Pass --password PW or set ORACLE_PWD in .env." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Every in-container command resolves ORACLE_HOME by globbing
# /opt/oracle/product/*/dbhomeFree. The directory is named after the marketing
# release ("26ai"), not the RU, so it is stable across 23.26.x -- but globbing
# means this keeps working if Oracle renames it.
ORAENV='export ORACLE_HOME=$(ls -d /opt/oracle/product/*/dbhomeFree); export ORACLE_SID=FREE; export PATH=$ORACLE_HOME/bin:$PATH;'

banner() { echo; echo "=================================================================="; echo "  $*"; echo "=================================================================="; }
step()   { echo; echo "-- $*"; }

# Run SQL from stdin as sysdba (OS auth -- no password needed).
sqlsys() { $CLI exec -i "$CONTAINER" bash -lc "$ORAENV sqlplus -s -L / as sysdba"; }

# Run a shell command inside the container with the Oracle environment set.
orash() { $CLI exec "$CONTAINER" bash -lc "$ORAENV $*"; }

# CDB$ROOT plus every open read-write PDB. Used for per-container work that
# catcon.pl does not drive. PDB$SEED is skipped: it is read-only, and the
# catcon-driven steps already reach it via --force_pdb_mode.
list_containers() {
  { sqlsys <<'SQL' | tr -d '\r ' | grep -E '^[A-Za-z][A-Za-z0-9_$]*$'
set pages 0 feed off head off
select 'CDB$ROOT' from dual
union all
select name from v$pdbs where open_mode = 'READ WRITE';
exit
SQL
} || echo 'CDB$ROOT'; }

# Run one or more scripts from a directory in EVERY container via catcon.pl.
# $1 = directory, $2 = log basename, rest = script names.
catcon() {
  local dir="$1" base="$2"; shift 2
  orash "mkdir -p /tmp/rurepair && cd /tmp/rurepair && \
    \$ORACLE_HOME/perl/bin/perl \$ORACLE_HOME/rdbms/admin/catcon.pl \
      -u \"sys/${SYS_PWD} as sysdba\" \
      -d $dir -l /tmp/rurepair -b '$base' \
      --force_pdb_mode 'READ WRITE' \
      -- $*" 2>&1 | grep -viE '^$|set_log_file_base_path' | tail -6 || true
  # catcon writes per-container logs; surface only real Oracle errors.
  local errs
  errs="$(orash "grep -hoE '^ORA-[0-9]+[^\"]*' /tmp/rurepair/${base}*.log 2>/dev/null | sort -u | head -10" || true)"
  if [ -n "$errs" ]; then
    echo "   Oracle errors reported by $base:"
    echo "$errs" | sed 's/^/     /'
  fi
}

# Build a "VIEW SCRIPT" map for every dictionary view the home can create.
#
# This is how the repair generalises: script names are never hardcoded, we ask
# the Oracle home which file defines the view that is missing.
#
# Line-based grep is NOT good enough here -- plenty of catalog scripts wrap the
# statement, for example:
#     CREATE OR REPLACE VIEW
#       DBA_END_USER_SECURITY_CONTEXT_ATTRIBUTES
# so DBA_END_USER_SECURITY_CONTEXT_ATTRIBUTES was silently classified as "not
# shipped in this home". Perl in slurp mode (-0777) matches across newlines and
# gets it right. Perl always exists at $ORACLE_HOME/perl/bin/perl.
#
# e*.sql / f*.sql are the DOWNGRADE scripts and also name these views; running
# one would remove the feature, so they are excluded.
VIEW_SCRIPT_MAP=""
build_view_map() {
  [ -n "$VIEW_SCRIPT_MAP" ] && return 0
  VIEW_SCRIPT_MAP="$(orash "cd \$ORACLE_HOME/rdbms/admin && \
    ls *.sql | grep -vE '^(e|f)[0-9]+\\.sql\$' | \
    xargs \$ORACLE_HOME/perl/bin/perl -0777 -ne \
      'while(/CREATE\\s+(?:OR\\s+REPLACE\\s+)?(?:FORCE\\s+)?VIEW\\s+(?:SYS\\.)?\"?([A-Za-z][A-Za-z0-9_]*)\"?/gi){ print uc(\$1),\" \",\$ARGV,\"\\n\" }' \
    | sort -u" || true)"
}

# NOTE: no early "exit" in awk and no "| head -1" here. Either one closes the
# pipe while echo is still writing, echo takes SIGPIPE, and because
# `set -o pipefail` is on the command substitution returns 141 -- which under
# `set -e` silently kills the whole script. That cost a full test cycle to
# find. Read the entire stream and keep only the first match instead.
find_view_script() {
  build_view_map
  echo "$VIEW_SCRIPT_MAP" | awk -v v="$1" '$1==v && !seen {print $2; seen=1}'
}

# Find the backport apply script that belongs to a given view.
#
# IMPORTANT, and non-obvious: you cannot grep the *_apply.sql scripts for the
# view name. An apply script only creates base tables and inserts privilege-map
# rows -- it never mentions the views. The matching *_rollback.sql DOES name
# them, because rolling back means dropping them.
#
# So the reliable rule is: find the *_rollback.sql that names the view, then
# take its sibling *_apply.sql if one exists. Verified for both known cases:
#   DBA_ASSERTIONS  -> bug_37454805_rollback.sql -> bug_37454805_apply.sql
#   DBA_DATA_GRANTS -> bug_38641243_rollback.sql -> bug_38641243_apply.sql
# (DBA_DATA_GRANTS also hits bug_38917915_rollback.sql, which has no apply
# sibling -- hence the existence test rather than blind name substitution.)
find_apply_scripts() {
  local view="$1"
  orash "for rb in \$(grep -lE '\\b${view}\\b' \$ORACLE_HOME/rdbms/admin/backport_files/*_rollback.sql 2>/dev/null); do
           ap=\$(echo \$rb | sed 's/_rollback\\.sql\$/_apply.sql/')
           [ -f \"\$ap\" ] && basename \$ap
         done | sort -u | head -4" || true
}

# ---------------------------------------------------------------------------
# Diagnosis
# ---------------------------------------------------------------------------
# Build a SQL list literal like 'A','B' from a whitespace-separated name list.
sql_in_list() { echo "$1" | tr -s '[:space:]' '\n' | grep -v '^$' | sed "s/.*/'&'/" | paste -sd, -; }

VIEW_LIST="$(sql_in_list "$ALL_PROBE_VIEWS")"

# Which of the probe views can THIS Oracle home actually create?
#
# The probe list spans several RUs, so on a 23.26.2 home the 23.26.3 views are
# legitimately absent from both the database and the home. Reporting those as
# "missing" would be a false alarm -- there is no script to run for them. One
# grep pass over the home separates "missing and fixable" from "not shipped in
# this release". Downgrade scripts (e*.sql / f*.sql) and the backport rollback
# scripts also contain the view names, so they are excluded here.
HOME_VIEWS_CACHE=""
home_defined_views() {
  if [ -z "$HOME_VIEWS_CACHE" ]; then
    build_view_map
    local out="" v
    for v in $ALL_PROBE_VIEWS; do
      if echo "$VIEW_SCRIPT_MAP" | awk -v n="$v" '$1==n {found=1} END {exit !found}'; then
        out="$out $v"
      fi
    done
    HOME_VIEWS_CACHE="$out"
  fi
  echo "$HOME_VIEWS_CACHE"
}

diagnose() {
  banner "1. Version: binaries versus dictionary"
  # dba_registry_history is the ONLY place the creating RU is recorded, and
  # datapatch overwrites it. Read it before doing anything else.
  sqlsys <<SQL
set pages 200 lines 200 feed off
col binary_version for a16
col dictionary_ru for a48
select (select version_full from v\$instance) as binary_version,
       (select max(comments) from dba_registry_history
         where comments like 'RDBMS%') as dictionary_ru
from dual;
prompt   (if these disagree, the volume was created by a different RU)
prompt   (if dictionary_ru already matches the binary but views are missing,
prompt    datapatch has been run and overwrote the evidence)
exit
SQL

  banner "2. Dictionary views that the Oracle home knows but the database lacks"
  local home_list
  home_list="$(sql_in_list "$(home_defined_views)")"
  [ -z "$home_list" ] && home_list="'~none~'"
  sqlsys <<SQL
set pages 300 lines 200 feed off
alter session set container = FREEPDB1;
col view_name for a46
col note for a34
with probes as (select column_value as name from table(sys.odcivarchar2list($VIEW_LIST))),
     inhome as (select column_value as name from table(sys.odcivarchar2list($home_list))),
     missing as (
       select p.name,
              case when h.name is null then 'not shipped in this home'
                   else 'MISSING - repairable' end as note
       from probes p
       left join dba_views d on d.owner = 'SYS' and d.view_name = p.name
       left join inhome  h on h.name = p.name
       where d.view_name is null)
select name as view_name, note from missing order by note, name;
prompt
with probes as (select column_value as name from table(sys.odcivarchar2list($VIEW_LIST))),
     inhome as (select column_value as name from table(sys.odcivarchar2list($home_list))),
     missing as (
       select p.name,
              case when h.name is null then 0 else 1 end as repairable
       from probes p
       left join dba_views d on d.owner = 'SYS' and d.view_name = p.name
       left join inhome  h on h.name = p.name
       where d.view_name is null)
select (select count(*) from probes)                             as probed,
       (select count(*) from missing where repairable = 1)        as repairable,
       (select count(*) from missing where repairable = 0)        as not_in_home
from dual;
exit
SQL

  banner "3. In-database JVM"
  # dba_registry lies here: it can report JAVAVM VALID while every Java call
  # fails. The only trustworthy check is to actually call into the JVM.
  sqlsys <<'SQL'
set pages 100 lines 200 feed off serveroutput on
declare v varchar2(4000);
begin
  v := dbms_java.longname('TEST');
  dbms_output.put_line('  JVM OK (dbms_java.longname returned ' || v || ')');
exception when others then
  dbms_output.put_line('  JVM BROKEN -> ' || sqlerrm);
  dbms_output.put_line('  fix: javavm/install/update_javavm_db.sql (NOT initjvm.sql)');
end;
/
select comp_id, status as registry_says from dba_registry where comp_id = 'JAVAVM';
exit
SQL

  banner "4. Invalid objects and components"
  sqlsys <<'SQL'
set pages 200 lines 200 feed off
col owner for a12
col object_name for a34
select count(*) as invalid_objects from cdb_objects where status <> 'VALID';
select con_id, owner, object_name, object_type from cdb_objects
where status <> 'VALID' and rownum <= 20 order by con_id, owner, object_name;
select con_id, comp_id, status from cdb_registry
where status not in ('VALID','OPTION OFF') order by con_id, comp_id;
exit
SQL
}

# ---------------------------------------------------------------------------
# Machine-readable summary (--summary)
# ---------------------------------------------------------------------------
# One "key=value" line per metric and nothing else, so CI can assert with
# `grep -qx`. Deliberately mirrors the style of .github/fixtures/upgrade/*.sql.
#
# Read-only. Safe to run against a production-ish database and safe to run as a
# pre-upgrade baseline: on a healthy database it must report
# missing_repairable=0 and jvm_ok=yes, which is what makes it a real test of the
# detector rather than just a bug reporter.
summarize() {
  local home_list
  home_list="$(sql_in_list "$(home_defined_views)")"
  [ -z "$home_list" ] && home_list="'~none~'"
  sqlsys <<SQL | tr -d '\r' | grep -E '^[a-z_]+=' || true
set pages 0 lines 300 feed off head off echo off serveroutput on
declare
  n number; v varchar2(200);
  procedure p(k varchar2, val varchar2) is begin dbms_output.put_line(k||'='||val); end;
begin
  select version_full into v from v\$instance;
  p('binary_version', v);

  begin
    select max(comments) into v from dba_registry_history where comments like 'RDBMS%';
  exception when others then v := 'unknown'; end;
  p('dictionary_ru', nvl(v,'unknown'));

  -- Probe-view accounting, computed exactly as the --check report does.
  select count(*) into n from table(sys.odcivarchar2list($VIEW_LIST));
  p('probe_views', to_char(n));

  select count(*) into n
    from (select column_value nm from table(sys.odcivarchar2list($VIEW_LIST))) p
    join (select column_value nm from table(sys.odcivarchar2list($home_list))) h
      on h.nm = p.nm
   where not exists (select 1 from dba_views d
                      where d.owner='SYS' and d.view_name = p.nm);
  p('missing_repairable', to_char(n));

  select count(*) into n
    from (select column_value nm from table(sys.odcivarchar2list($VIEW_LIST))) p
   where not exists (select 1 from dba_views d
                      where d.owner='SYS' and d.view_name = p.nm)
     and not exists (select 1 from table(sys.odcivarchar2list($home_list)) h
                      where h.column_value = p.nm);
  p('missing_not_in_home', to_char(n));

  -- The JVM check that dba_registry cannot be trusted for.
  begin
    v := dbms_java.longname('TEST');
    p('jvm_ok', 'yes');
  exception when others then p('jvm_ok', 'no');
  end;
  select max(status) into v from dba_registry where comp_id = 'JAVAVM';
  p('javavm_registry', nvl(v,'absent'));

  select count(*) into n from cdb_registry where status not in ('VALID','OPTION OFF');
  p('non_valid_components', to_char(n));

  select count(*) into n from cdb_objects where status <> 'VALID';
  p('invalid_objects', to_char(n));
  select count(*) into n from cdb_objects where owner = 'SYS' and status <> 'VALID';
  p('sys_invalid_objects', to_char(n));

  -- Assertions are the canary feature for this whole class of problem: base
  -- tables shipped in 23.26.0 but views + privileges only in 23.26.1.
  select count(*) into n from dba_views where view_name like '%ASSERTION%';
  p('assertion_views', to_char(n));
  select count(*) into n from system_privilege_map where name like '%ASSERTION%';
  p('assertion_privs', to_char(n));
  select count(*) into n from sys.registry\$backports;
  p('registry_backports', to_char(n));
end;
/
exit
SQL
}

# ---------------------------------------------------------------------------
# Repair
# ---------------------------------------------------------------------------
# Only views that are BOTH absent from the database and creatable from this
# home. Anything the home cannot create has no script to run, so feeding it to
# the repair would just produce noise.
missing_views() {
  local home_list
  home_list="$(sql_in_list "$(home_defined_views)")"
  [ -z "$home_list" ] && home_list="'~none~'"
  sqlsys <<SQL | tr -d '\r' | grep -E '^[A-Z][A-Z0-9_]+$' || true
set pages 0 lines 200 feed off head off
alter session set container = FREEPDB1;
select p.name
from (select column_value as name from table(sys.odcivarchar2list($VIEW_LIST))) p
join (select column_value as name from table(sys.odcivarchar2list($home_list))) h
  on h.name = p.name
where not exists (select 1 from dba_views d where d.owner='SYS' and d.view_name = p.name)
order by 1;
exit
SQL
}

# NOTE: set -o pipefail is on, so a grep that matches nothing would fail the
# whole assignment and (with set -e) kill the script. Every such pipeline here
# ends in "|| echo 0" / "|| true" for that reason.
# Counts INVALID objects owned by SYS only -- deliberately not all objects.
#
# This feeds the "is there anything to repair" gate, and the tool's business is
# the dictionary. An application schema with an invalid package (a broken
# dependency, a half-finished migration) is none of its concern, and counting
# those would make the gate never say "nothing to repair" on a real database.
count_sys_invalid() { { sqlsys <<'SQL' | tr -d '\r ' | awk '/^[0-9]+$/ && !seen {print; seen=1}'
set pages 0 feed off head off
select count(*) from cdb_objects where owner = 'SYS' and status <> 'VALID';
exit
SQL
} || echo 0; }
jvm_is_broken() { sqlsys <<'SQL' | grep -q 'JVM_BROKEN'
set pages 0 feed off head off serveroutput on
begin declare v varchar2(4000);
  begin v := dbms_java.longname('TEST');
  exception when others then dbms_output.put_line('JVM_BROKEN'); end;
end;
/
exit
SQL
}

repair() {
  banner "REPAIR STEP 1: reload the catalog scripts for the affected features"

  # Decide whether there is anything to do at all. Running catalog scripts
  # against a healthy database is pointless and still rewrites SYS rows, so a
  # clean database is left alone.
  # The gate is deliberately "missing views OR broken JVM" and does NOT include
  # the invalid-SYS-object count. Those objects can be invalid for reasons that
  # have nothing to do with an RU gap (audit configuration, a half-finished
  # migration), and some are not fixable by reloading catalog scripts at all.
  # Including them would mean this tool never reports "nothing to repair" on a
  # real database, and would make a second --repair run look necessary forever.
  # When a repair does run, the heal loop in step 2 attacks whatever invalid SYS
  # package bodies exist anyway.
  local missing
  missing="$(missing_views)"
  if [ -z "$missing" ] && ! jvm_is_broken; then
    echo "  Nothing to repair: no missing views and the JVM is healthy."
    echo "  (invalid SYS objects, if any: $(count_sys_invalid) -- not repairable by this tool)"
    # Step 4 still runs: a stale component flag is repairable on its own, and
    # skipping it here would leave JAVAVM INVALID forever after a JVM reload.
    revalidate_invalid_components
    return 0
  fi
  echo "  Missing (repairable) views: ${missing:-none}" | tr '\n' ' '; echo

  # Resolve scripts for EVERY probe view this home can create, not only the
  # ones currently missing.
  #
  # Why not just the missing ones: a half-repaired database can have the views
  # present while the privilege-map rows are absent (that is exactly what an
  # earlier buggy version of this script produced -- 12 assertion views, 0
  # assertion privileges, so `create assertion` still failed with ORA-00901).
  # Keying off missing views alone would never fix that.
  #
  # This is safe because Oracle writes these scripts to be re-runnable:
  # the view scripts are CREATE OR REPLACE, and every privilege-map INSERT in
  # an apply script is preceded by a DELETE of the same key, with
  # registry$backports using IGNORE_ROW_ON_DUPKEY. datapatch may re-run them
  # too.
  local view vscript ascript vscripts="" ascripts=""
  for view in $(home_defined_views); do
    vscript="$(find_view_script "$view")"
    [ -z "$vscript" ] && continue
    case " $vscripts " in *" $vscript "*) ;; *) vscripts="$vscripts $vscript" ;; esac
    for ascript in $(find_apply_scripts "$view"); do
      case " $ascripts " in *" $ascript "*) ;; *) ascripts="$ascripts $ascript" ;; esac
    done
  done
  echo "  View scripts:   ${vscripts:-(none)}"
  echo "  Apply scripts:  ${ascripts:-(none)}"

  # Order is deliberate: base tables and privileges first, then the views on
  # top of them. The other way round leaves the views invalid, because they
  # select from base tables that do not exist yet.
  if [ -n "$ascripts" ]; then
    step "Running backport apply scripts (base tables, privileges, registry\$backports)"
    catcon '$ORACLE_HOME/rdbms/admin/backport_files' rurepair_apply $ascripts
  fi
  if [ -n "$vscripts" ]; then
    step "Running view scripts"
    catcon '$ORACLE_HOME/rdbms/admin' rurepair_views $vscripts
  fi

  banner "REPAIR STEP 2: recompile, then heal invalid SYS package bodies"
  # An apply script can change a base table's shape while the package bodies
  # still in the dictionary were compiled against the old shape -- that is the
  # ORA-00947 failure on XS_DATA_SECURITY_INT / XS_SECURITY_CLASS_INT. Reload
  # the .plb that defines each invalid body, then recompile again. Bounded to 3
  # rounds so a genuinely unfixable object cannot spin forever.
  local round bodies body plb plbs
  for round in 1 2 3; do
    step "Recompile round $round (utlrp.sql)"
    catcon '$ORACLE_HOME/rdbms/admin' "rurepair_utlrp$round" utlrp.sql

    bodies="$(sqlsys <<'SQL' | tr -d '\r' | grep -E '^[A-Z][A-Z0-9_$]+$' || true
set pages 0 lines 200 feed off head off
select distinct object_name from cdb_objects
where owner = 'SYS' and object_type = 'PACKAGE BODY' and status <> 'VALID'
order by 1;
exit
SQL
)"
    if [ -z "$bodies" ]; then
      echo "  No invalid SYS package bodies. Heal loop done."
      break
    fi
    echo "  Invalid SYS package bodies:"; echo "$bodies" | sed 's/^/    /'

    plbs=""
    for body in $bodies; do
      # The wrapped body lives in a .plb; find the one that declares it.
      plb="$(orash "grep -lE 'PACKAGE BODY +${body}\\b' \$ORACLE_HOME/rdbms/admin/*.plb 2>/dev/null | head -1 | xargs -r basename" || true)"
      if [ -n "$plb" ]; then
        case " $plbs " in *" $plb "*) ;; *) plbs="$plbs $plb" ;; esac
      else
        echo "    WARNING: no .plb found for $body"
      fi
    done
    if [ -z "$plbs" ]; then
      echo "  Nothing left to reload; stopping heal loop."
      break
    fi
    step "Reloading package bodies: $plbs"
    catcon '$ORACLE_HOME/rdbms/admin' "rurepair_plb$round" $plbs
  done

  banner "REPAIR STEP 3: in-database JVM"
  # Only touch the JVM if it is actually broken -- reloading it is expensive
  # (about 33k Java classes) and pointless on a healthy database.
  if jvm_is_broken; then
    step "JVM is broken (ORA-29548) -- running update_javavm_db.sql"
    echo "  Note: initjvm.sql is the WRONG tool, it refuses with ORA-29539."
    catcon '$ORACLE_HOME/javavm/install' rurepair_jvm update_javavm_db.sql
  else
    echo "  JVM already healthy -- skipping."
  fi

  revalidate_invalid_components
}

# REPAIR STEP 4 -- refresh the status flag of INVALID components only.
#
# DO NOT use dbms_registry_sys.validate_components here.
#
# It marks EVERY component INVALID and then revalidates them all. On a real
# install that includes APEX that left APEX INVALID in dba_registry even though
# all 4492 APEX objects were VALID and `validate_apex` run on its own succeeds
# and restores VALID. A self-inflicted regression: the dictionary repair would
# "succeed" while reporting APEX as broken.
#
# So: only touch components that are ALREADY INVALID, and revalidate each by
# calling the procedure the registry itself nominates
# (dba_registry.procedure -- INITJVMAUX.VALIDATE_JAVAVM for JAVAVM,
# VALIDATE_APEX for APEX). Anything already VALID is left alone.
#
# This runs even when steps 1-3 find nothing to do, because a stale component
# flag is its own repairable condition: update_javavm_db.sql leaves JAVAVM
# INVALID with a perfectly working JVM, and nothing else clears it.
revalidate_invalid_components() {
  banner "REPAIR STEP 4: refresh the status flag of INVALID components only"
  local con
  for con in $(list_containers); do
    echo "  -- container $con"
    # NOTE: "procedure" must be aliased. It is a PL/SQL reserved word, so the
    # record field reference c.procedure raises ORA-06550 even though the column
    # selects fine in plain SQL. That silently skipped this whole step once.
    sqlsys <<SQL
set feed off serveroutput on lines 200 pages 0
alter session set container = $con;
set serveroutput on
declare
  n number := 0;
begin
  for c in (select comp_id, procedure as proc_name
              from dba_registry
             where status = 'INVALID'
               and procedure is not null) loop
    n := n + 1;
    begin
      execute immediate 'begin ' || c.proc_name || '; end;';
      dbms_output.put_line('     revalidated ' || c.comp_id || ' via ' || c.proc_name);
    exception when others then
      dbms_output.put_line('     ' || c.comp_id || ' validation FAILED: ' || sqlerrm);
    end;
  end loop;
  if n = 0 then
    dbms_output.put_line('     no INVALID components -- nothing to revalidate');
  end if;
end;
/
exit
SQL
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ "$MODE" = "summary" ]; then
  summarize
  exit 0
fi

banner "26ai RU dictionary check -- container: $CONTAINER (mode: $MODE)"
diagnose

if [ "$MODE" = "repair" ]; then
  if [ "$ASSUME_YES" != "true" ]; then
    echo
    echo "This will run Oracle catalog scripts against every container in $CONTAINER."
    echo "It changes SYS objects. Back up the volume first if the data matters."
    printf "Continue? [y/N] "
    read -r reply
    case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 1 ;; esac
  fi
  repair
  banner "POST-REPAIR VERIFICATION"
  diagnose
  echo
  echo "Expected end state: 0 missing views, JVM OK, 0 invalid objects,"
  echo "no components outside VALID / OPTION OFF."
  echo
  echo "The dictionary_ru marker does NOT change -- no supported tool updates"
  echo "it. Its disagreement with the binary version is now cosmetic."
fi
