-- Read-only checks for the data dictionary itself, run as SYS.
-- Emits one `key=value` line per metric (via dbms_output) so the workflow can
-- grep -qx each.
--
-- WHY THIS FIXTURE EXISTS
--
-- Changing the DB image tag on an existing oradata volume does NOT upgrade the
-- data dictionary. The Oracle Free entrypoint only relinks the configuration
-- files and opens whatever database is already on the volume -- there is no
-- upgrade code in it at all. The container reports healthy, every row and
-- object stays valid, and nothing is logged beyond "No patches have been
-- applied".
--
-- What silently goes missing is every dictionary object that a skipped release
-- update added, plus the in-database JVM. Neither `datapatch` nor
-- `catctl.pl catupgrd.sql` repairs it: datapatch matches on the RU patch ID
-- (identical across 23.26.x) and reports "No release update patches need to be
-- installed", while catupgrd compares only "23.0.0.0.0" and reports "Container
-- Database is already at current version".
--
-- Measured on a real 23.26.0 -> 23.26.2 swap: 18 dictionary views missing
-- (9 assertion views added in RU 23.26.1, 9 Deep Data Security views added in
-- RU 23.26.2) and a broken JVM.
--
-- See scripts/repair-ru-dictionary.sh for the repair and the full write-up.
--
-- TRAP: dba_registry reports JAVAVM VALID even when every Java call raises
-- ORA-29548. The registry status is a stale flag, so it is NOT a usable health
-- check. Only actually calling into the JVM is. Both are emitted below so the
-- difference is visible.
--
-- Run as SYS, e.g.:
--   sql -name local-26ai-sys @.github/fixtures/upgrade/verify-dictionary.sql
--
-- This script mutates nothing.

set serveroutput on size unlimited
set heading off feedback off pagesize 0 verify off trimspool on
whenever sqlerror exit failure

declare
  n number;
  v varchar2(4000);

  procedure p(k varchar2, val varchar2) is
  begin
    dbms_output.put_line(k || '=' || val);
  end;
begin
  -- The binaries.
  select version_full into v from v$instance;
  p('binary_version', v);

  -- The dictionary's provenance: which RU actually built this database.
  --
  -- This is the ONLY record of the creating RU, and `datapatch` OVERWRITES it
  -- while applying zero dictionary changes -- so read it before ever running
  -- datapatch on a swapped volume, or the evidence is gone.
  begin
    select max(comments) into v
      from dba_registry_history
     where comments like 'RDBMS%';
  exception
    when others then v := null;
  end;
  p('dictionary_ru', nvl(v, 'unknown'));

  -- The in-database JVM. Call it; do not trust the registry.
  begin
    v := dbms_java.longname('TEST');
    p('jvm_ok', 'yes');
  exception
    when others then p('jvm_ok', 'no');
  end;
  select max(status) into v from dba_registry where comp_id = 'JAVAVM';
  p('javavm_registry', nvl(v, 'absent'));

  -- Component and object health across every container.
  select count(*) into n
    from cdb_registry
   where status not in ('VALID', 'OPTION OFF');
  p('non_valid_components', to_char(n));

  select count(*) into n from cdb_objects where owner = 'SYS' and status <> 'VALID';
  p('sys_invalid_objects', to_char(n));

  -- SQL Assertions are the canary for this whole class of problem: the six
  -- ASSERT*$ base tables ship in 23.26.0, but the views and the privilege-map
  -- rows only arrive in 23.26.1. A swapped database therefore has the tables
  -- and neither of the rest, which is why `grant create assertion` succeeds
  -- (the privilege is compiled into the binary) while DBA_ASSERTIONS raises
  -- ORA-00942.
  --
  -- Expected on a healthy 23.26.1+ database: 12 views (DBA/ALL/USER/CDB x
  -- ASSERTIONS, ASSERTION_DEPENDENCIES, ASSERTION_LOCK_MATRIX) and 4 privileges.
  select count(*) into n from dba_views where view_name like '%ASSERTION%';
  p('assertion_views', to_char(n));
  select count(*) into n from system_privilege_map where name like '%ASSERTION%';
  p('assertion_privs', to_char(n));
  select count(*) into n from dba_tables
   where owner = 'SYS' and table_name like 'ASSERT%$';
  p('assertion_base_tables', to_char(n));

  -- Views added in RU 23.26.2 (Deep Data Security). Present on a healthy
  -- 23.26.2 database, absent on a volume created by 23.26.0 or 23.26.1.
  select count(*) into n
    from dba_views
   where view_name in ('DBA_DATA_GRANTS', 'ALL_DATA_GRANTS', 'USER_DATA_GRANTS',
                       'DBA_DATA_ROLES', 'DBA_DATA_ROLE_GRANTS',
                       'DBA_APPLICATION_IDENTITIES',
                       'DBA_END_USER_SECURITY_CONTEXTS',
                       'DBA_END_USER_SECURITY_CONTEXT_ATTRIBUTES',
                       'DBA_END_USER_SECURITY_CONTEXT_DATA_ROLES');
  p('ddsec_views', to_char(n));

  -- Backports recorded by an apply script. 0 on a stock image (the RU is built
  -- into the binaries, not applied as a patch); non-zero once
  -- scripts/repair-ru-dictionary.sh has run.
  select count(*) into n from sys.registry$backports;
  p('registry_backports', to_char(n));
end;
/

exit
