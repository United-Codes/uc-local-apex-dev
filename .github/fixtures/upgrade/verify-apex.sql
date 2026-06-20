-- Read-only integrity checks for the live APEX schema, run as SYS.
-- Emits one `key=value` line per metric (via dbms_output) so the workflow can
-- grep -qx each, and so a full baseline-vs-post diff proves nothing was lost.
--
-- The APEX schema name embeds the APEX version (e.g. APEX_260100), and an older
-- schema (e.g. APEX_240200) may linger after an APEX upgrade. We therefore
-- resolve the *current* schema dynamically from dba_registry rather than
-- hardcoding it, so this fixture survives future APEX version bumps.
--
-- A DB-image patch upgrade does not change the APEX version, so every emitted
-- value is identical before and after an in-place upgrade -- hence the workflow
-- can assert exact equality without pinning any version-specific count.
--
-- Run as SYS, e.g.:
--   sql -name local-26ai-sys @.github/fixtures/upgrade/verify-apex.sql
--
-- This script mutates nothing (read-only dictionary + APEX view queries).

set serveroutput on size unlimited
set heading off feedback off pagesize 0 verify off trimspool on
whenever sqlerror exit failure

declare
  l_schema dba_registry.schema%type;
  l_status dba_registry.status%type;
  l_ver    varchar2(50);
  n        number;

  procedure p(k varchar2, v varchar2) is
  begin
    dbms_output.put_line(k || '=' || v);
  end;

  -- Object count of a given type in the resolved APEX schema.
  function cnt(t varchar2) return number is
    c number;
  begin
    select count(*) into c
      from dba_objects
     where owner = l_schema
       and object_type = t;
    return c;
  end;
begin
  -- Authoritative current APEX owner + registry health.
  select schema, status into l_schema, l_status
    from dba_registry
   where comp_id = 'APEX';
  p('apex_registry_status', l_status);

  select version_no into l_ver from apex_release;
  p('apex_version', l_ver);

  -- No APEX object may be left INVALID by the upgrade.
  select count(*) into n
    from dba_objects
   where owner = l_schema
     and status = 'INVALID';
  p('apex_invalid', to_char(n));

  -- Total + per-type object counts (compared before/after).
  select count(*) into n from dba_objects where owner = l_schema;
  p('apex_objects',        to_char(n));
  p('apex_packages',       to_char(cnt('PACKAGE')));
  p('apex_package_bodies', to_char(cnt('PACKAGE BODY')));
  p('apex_views',          to_char(cnt('VIEW')));
  p('apex_triggers',       to_char(cnt('TRIGGER')));
  p('apex_types',          to_char(cnt('TYPE')));
  p('apex_type_bodies',    to_char(cnt('TYPE BODY')));
  p('apex_tables',         to_char(cnt('TABLE')));
  p('apex_indexes',        to_char(cnt('INDEX')));
  p('apex_sequences',      to_char(cnt('SEQUENCE')));
  p('apex_jobs',           to_char(cnt('JOB')));

  -- Functional probes: the public APEX dictionary views must be queryable.
  -- They only print `yes` if the query succeeds; any failure is turned into a
  -- hard error by `whenever sqlerror exit failure` above.
  select count(*) into n from apex_applications where rownum <= 1;
  p('apex_apps_view_ok', 'yes');

  select count(*) into n from apex_workspaces where rownum <= 1;
  p('apex_workspaces_view_ok', 'yes');
end;
/

exit
