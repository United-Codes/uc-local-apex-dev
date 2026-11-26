-- Prints one "key|value" line for every fixture. scripts/test-backup-fixtures.sh
-- runs it before and after a backup and restore, and compares the two outputs.
-- A probe that fails prints "ERR". It never stops the run.

-- @dblinter ignore(G-7310,G-7410,G-3110,G-4320,G-7150,G-9108,G-9102,G-9501,G-5010)
set define off feedback off heading off pagesize 0 linesize 1000 trimspool on serveroutput on size unlimited termout on verify off echo off
declare
  procedure p(k in varchar2, q in varchar2) is
    v varchar2(4000 char);
  begin
    begin
      execute immediate q into v;
    exception when no_data_found then v := '-';
              when others then v := 'ERR';
    end;
    sys.dbms_output.put_line(k || '|' || nvl(v, '-'));
  end p;
begin
  p('user.fxa',        q'[select default_tablespace||','||temporary_tablespace||','||profile from dba_users where username='FXA']');
  p('user.fxb',        q'[select default_tablespace||','||profile from dba_users where username='FXB']');
  p('user.fxa.pwhash', q'[select case when password_versions is not null then 'has' end from dba_users where username='FXA']');
  p('tablespace.fx',   q'[select count(*) from dba_tablespaces where tablespace_name='TBS_FX']');
  p('quota.fxa',       q'[select max_bytes from dba_ts_quotas where username='FXA' and tablespace_name='TBS_FX']');
  p('profile.fx',      q'[select listagg(resource_name||'='||limit,',') within group (order by resource_name) from dba_profiles where profile='FX_PROFILE' and resource_name in ('SESSIONS_PER_USER','IDLE_TIME','PASSWORD_LIFE_TIME')]');
  p('role.fx',         q'[select count(*) from dba_roles where role='FX_ROLE']');
  p('rolegrant.fxa',   q'[select listagg(granted_role,',') within group (order by granted_role) from dba_role_privs where grantee='FXA']');
  p('rolegrant.fxb',   q'[select listagg(granted_role,',') within group (order by granted_role) from dba_role_privs where grantee='FXB']');
  p('sysprivs.fxa',    q'[select listagg(privilege,',') within group (order by privilege) from dba_sys_privs where grantee='FXA']');
  p('sysprivs.fxb',    q'[select listagg(privilege,',') within group (order by privilege) from dba_sys_privs where grantee='FXB']');
  p('sysprivs.role',   q'[select listagg(privilege,',') within group (order by privilege) from dba_sys_privs where grantee='FX_ROLE']');
  p('objgrants.fxa',   q'[select listagg(owner||'.'||table_name||':'||privilege,',') within group (order by owner,table_name,privilege) from dba_tab_privs where grantee='FXA' and table_name not like 'QT%\_BUFFER' escape '\' and table_name not like '%BQVIEW']');
  p('objgrants.fxb',   q'[select listagg(owner||'.'||table_name||':'||privilege,',') within group (order by owner,table_name,privilege) from dba_tab_privs where grantee='FXB']');
  p('objgrants.role',  q'[select listagg(owner||'.'||table_name||':'||privilege,',') within group (order by owner,table_name,privilege) from dba_tab_privs where grantee='FX_ROLE']');
  p('objgrants.public',q'[select listagg(owner||'.'||table_name,',') within group (order by owner,table_name) from dba_tab_privs where grantee='PUBLIC' and owner in ('FXA','FXB')]');
  p('grantoption',     q'[select listagg(grantee||':'||grantable,',') within group (order by grantee) from dba_tab_privs where owner='FXA' and table_name='T' and grantee='FXB']');
  p('colgrants.fxa',   q'[select listagg(owner||'.'||table_name||'.'||column_name||':'||privilege,',') within group (order by column_name) from dba_col_privs where grantee='FXA']');
  p('synonym.public',  q'[select listagg(synonym_name||'->'||table_owner||'.'||table_name,',') within group (order by synonym_name) from dba_synonyms where owner='PUBLIC' and synonym_name like 'FX\_%' escape '\']');
  p('synonym.private', q'[select listagg(owner||'.'||synonym_name||'->'||table_owner||'.'||table_name,',') within group (order by owner) from dba_synonyms where owner in ('FXA','FXB')]');
  p('directory.fx',    q'[select directory_path from dba_directories where directory_name='FX_DIR']');
  p('directory.priv',  q'[select listagg(grantee||':'||privilege,',') within group (order by grantee,privilege) from dba_tab_privs where table_name='FX_DIR']');
  p('ace.fxa',         q'[select listagg(host||':'||privilege,',') within group (order by host,privilege) from dba_host_aces where principal='FXA']');
  p('credential.fx',   q'[select count(*) from dba_credentials where owner='FXA' and credential_name='FX_CRED']');
  p('dblink.private',  q'[select count(*) from dba_db_links where owner='FXA' and db_link like 'FX_LINK%']');
  p('dblink.public',   q'[select count(*) from dba_db_links where owner='PUBLIC' and db_link like 'FX_PUBLIC_LINK%']');
  p('dblink.host',     q'[select listagg(owner||':'||host,',') within group (order by owner) from dba_db_links where db_link like 'FX\_%' escape '\']');
  p('context.fx',      q'[select schema||'.'||package from dba_context where namespace='FX_CTX']');
  p('vpd.policy',      q'[select count(*) from dba_policies where object_owner='FXA' and policy_name='FX_P1']');
  p('redact.policy',   q'[select count(*) from redaction_policies where object_owner='FXA' and policy_name='FX_R1']');
  p('job.fxa',         q'[select listagg(job_name||':'||enabled,',') within group (order by job_name) from dba_scheduler_jobs where owner='FXA']');
  p('job.fxb',         q'[select listagg(job_name||':'||enabled,',') within group (order by job_name) from dba_scheduler_jobs where owner='FXB']');
  p('program.fxa',     q'[select count(*) from dba_scheduler_programs where owner='FXA']');
  p('schedule.fxa',    q'[select count(*) from dba_scheduler_schedules where owner='FXA']');
  p('jobclass.fx',     q'[select count(*) from dba_scheduler_job_classes where job_class_name='FX_CLASS']');
  p('aq.queue',        q'[select count(*) from dba_queues where owner='FXA' and name='Q']');
  p('mle.module',      q'[select count(*) from dba_objects where owner='FXA' and object_type='MLE MODULE']');
  p('domain',          q'[select count(*) from dba_domains where owner='FXA' and name='EMAIL_D']');
  p('propgraph',       q'[select count(*) from dba_property_graphs where owner='FXA' and graph_name='G']');
  p('index.text',      q'[select index_type||':'||status from dba_indexes where owner='FXA' and index_name='TI']');
  p('index.vector',    q'[select index_type||':'||status from dba_indexes where owner='FXA' and index_name='VI']');
  p('ctx.preference',  q'[select count(*) from ctx_user_preferences]');
  p('audit.policy',    q'[select count(*) from audit_unified_policies where policy_name='FX_AUDIT_POL']');
  p('rows.fxa.t',      q'[select count(*)||','||min(vector_dimension_count(emb)) from fxa.t]');
  p('rows.fxa.docs',   q'[select count(*) from fxa.docs]');
  p('rows.fxb.t',      q'[select count(*) from fxb.t]');
  p('rows.fxa.t_vpd',  q'[select count(*) from fxa.t_vpd]');
  p('rows.fxa.t_red',  q'[select count(*) from fxa.t_red]');
  p('sequence.fxa.s',  q'[select to_char(last_number) from dba_sequences where sequence_owner='FXA' and sequence_name='S']');
  p('invalid.fxa',     q'[select count(*) from dba_objects where owner in ('FXA','FXB') and status<>'VALID']');
  p('apex.workspace',  q'[select count(*) from apex_workspaces where workspace='FXA']');
  p('apex.user',       q'[select count(*) from apex_workspace_apex_users where workspace_name='FXA' and user_name='FXUSER']');
  p('apex.credential', q'[select listagg(static_id,',') within group (order by static_id) from apex_workspace_credentials where workspace='FXA']');
  p('apex.smtp',       q'[select apex_instance_admin.get_parameter('SMTP_HOST_ADDRESS') from dual]');
  p('apex.mailqueue',  q'[select count(*) from apex_260200.wwv_flow_mail_queue where mail_to='fx@example.com']');
  p('ords.schema',     q'[select status||','||auto_rest_auth from ords_metadata.ords_schemas where parsing_schema='FXA']');
  p('ords.module',     q'[select count(*) from ords_metadata.ords_modules m join ords_metadata.ords_schemas s on s.id=m.schema_id where s.parsing_schema='FXA']');
  p('rsrc.group',      q'[select consumer_group||','||comments from dba_rsrc_consumer_groups where consumer_group='FX_GROUP' and status is null]');
  p('rsrc.plan',       q'[select listagg(group_or_subplan||':'||mgmt_p1||':'||utilization_limit||':'||max_idle_time,',') within group (order by group_or_subplan) from dba_rsrc_plan_directives where plan='FX_PLAN' and status is null]');
  p('rsrc.mapping',    q'[select consumer_group from dba_rsrc_group_mappings where attribute='ORACLE_USER' and value='FXB' and status is null]');
  p('rsrc.switch',     q'[select listagg(grantee||':'||granted_group,',') within group (order by grantee) from dba_rsrc_consumer_group_privs where granted_group='FX_GROUP']');
  p('jobclass.attrs',  q'[select resource_consumer_group||','||logging_level||','||log_history||','||comments from dba_scheduler_job_classes where job_class_name='FX_CLASS']');
  p('schedule.sys',    q'[select repeat_interval from dba_scheduler_schedules where owner='SYS' and schedule_name='FX_WIN_SCHED']');
  p('window.fx',       q'[select listagg(window_name||':'||resource_plan||':'||schedule_name||':'||repeat_interval||':'||duration||':'||enabled,',') within group (order by window_name) from dba_scheduler_windows where window_name like 'FX\_WIN%' escape '\']');
  p('window.group',    q'[select listagg(group_name||':'||member_name,',') within group (order by group_name,member_name) from dba_scheduler_group_members where member_name like '%FX\_WIN%' escape '\']');
  p('job.window',      q'[select schedule_name||':'||schedule_type from dba_scheduler_jobs where owner='FXA' and job_name='J_WIN']');
  p('edition',         q'[select listagg(edition_name||':'||parent_edition_name,',') within group (order by edition_name) from dba_editions where edition_name='FX_E1']');
  p('edition.user',    q'[select editions_enabled from dba_users where username='FXB']');
  p('edition.grant',   q'[select listagg(grantee||':'||privilege,',') within group (order by grantee) from dba_tab_privs where type='EDITION' and table_name='FX_E1']');
  p('edition.object',  q'[select count(*) from dba_objects_ae where owner='FXB' and object_name='P_ED']');
  p('proxy',           q'[select listagg(proxy||'>'||client,',') within group (order by proxy) from proxy_users where proxy='FXB']');
  p('role.password',   q'[select authentication_type from dba_roles where role='FX_ROLE2']');
  p('defaultroles.fxa',q'[select listagg(granted_role||':'||default_role,',') within group (order by granted_role) from dba_role_privs where grantee='FXA']');
  p('directory.fx2',   q'[select directory_path from dba_directories where directory_name='FX_DIR2']');
  p('directory.priv2', q'[select listagg(grantee||':'||privilege,',') within group (order by grantee,privilege) from dba_tab_privs where table_name='FX_DIR2']');
  p('exttable.rows',   q'[select count(*)||','||max(name) from fxa.ext_t]');
  p('bfile.length',    q'[select dbms_lob.getlength(f) from fxa.t_bfile where id=1]');
  p('ace.deny',        q'[select grant_type from dba_host_aces where host='deny.example.com' and principal='FXB']');
  p('ace.role',        q'[select privilege||','||to_char(end_date,'YYYY') from dba_host_aces where host='role.example.com' and principal='FX_ROLE']');
  p('ace.public',      q'[select privilege from dba_host_aces where host='public.example.com' and principal='PUBLIC']');
  p('ace.wallet',      q'[select privilege from dba_wallet_aces where wallet_path like '%fx_wallet' and principal='FXA']');
  p('synonym.remote',  q'[select table_owner||'.'||table_name||'@'||db_link from dba_synonyms where owner='PUBLIC' and synonym_name='FX_REMOTE']');
  p('vpd.relcols',     q'[select listagg(sec_rel_column||':'||column_option,',') within group (order by sec_rel_column) from dba_sec_relevant_cols where object_owner='FXA' and policy_name='FX_P2']');
  p('envuser.settings',q'[select u.profile||','||(select max_bytes from dba_ts_quotas q where q.username=u.username and q.tablespace_name='TBS_FX') from dba_users u where u.profile='FX_PROFILE' and u.username not in ('FXA')]');
  p('spm.baseline',    q'[select count(*) from dba_sql_plan_baselines where parsing_schema_name='FXA']');
  p('firewall.list',   q'[select count(*) from dba_sql_firewall_allow_lists where username='FXB']');
  p('assertions',      q'[select listagg(assertion_name||':'||deferrable||':'||deferred,',') within group (order by assertion_name) from dba_assertions where owner='FXA']');
  p('schemapriv',      q'[select listagg(grantee||':'||privilege||':'||schema,',') within group (order by grantee) from dba_schema_privs where schema='FXB']');
  p('ords.objects',   q'[select count(*) from ords_metadata.ords_objects o join ords_metadata.ords_schemas s on s.id=o.schema_id where s.parsing_schema='FXA']');
end;
/
exit
