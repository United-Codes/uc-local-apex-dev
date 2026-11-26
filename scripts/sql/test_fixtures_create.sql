-- Fixtures for the backup/restore test (scripts/test-backup-fixtures.sh).
--
-- Everything here is created by hand with plain SQL as SYS. The schemas FXA and
-- FXB are NOT created with create-user.sh and are NOT in .env. That is the
-- point: a backup must find them anyway, and it must carry what a schema export
-- does not carry.
--
-- Every statement runs on its own. A failure only means that the feature is not
-- available. The probe (test_fixtures_probe.sql) shows what exists.

-- @dblinter ignore(G-7310,G-7410,G-3110,G-4320,G-7150,G-9108,G-9102,G-9501,G-5010,G-4395,G-2135)
whenever sqlerror continue
set define off echo off feedback off serveroutput on size unlimited
-- &env_user is a schema from .env. test-backup-fixtures.sh defines it.
set define on

prompt == tablespace, profile, users
create tablespace tbs_fx datafile 'tbs_fx.dat' size 10m reuse autoextend on next 2m maxsize 200m;
create profile fx_profile limit sessions_per_user 7 idle_time 90 password_life_time unlimited;
create user fxa identified by "Fx_Pw_12345a#" default tablespace tbs_fx temporary tablespace temp profile fx_profile quota 50m on tbs_fx;
create user fxb identified by "Fx_Pw_12345b#" default tablespace users quota 10m on users;
grant create session, create table, create view, create sequence, create procedure, create synonym, create job, create type, create trigger to fxa;
grant create session, create table, create view, create procedure, create job to fxb;
grant unlimited tablespace to fxb;

prompt == custom role, role grants, system privileges beyond the usual
create role fx_role;
grant create session to fx_role;
grant fx_role to fxa;
grant create mle to fxa;
grant execute on javascript to fxa;
grant execute dynamic mle to fxa;
grant create domain to fxa;
grant create property graph to fxa;
grant create any context to fxa;
grant create database link to fxa;
grant db_developer_role to fxa;
grant soda_app to fxa;
grant ctxapp to fxa;
grant execute on dbms_aq to fxa;
grant aq_administrator_role to fxa;
grant select_catalog_role to fxb;

prompt == objects
create table fxa.t (id number generated always as identity primary key, secret varchar2(100 char), emb vector(3, float32));
insert into fxa.t (secret, emb) values ('one', '[1,2,3]');
insert into fxa.t (secret, emb) values ('two', '[2,3,4]');
insert into fxa.t (secret, emb) values ('three', '[3,4,5]');
commit;
create table fxa.docs (id number primary key, txt varchar2(4000 char));
insert into fxa.docs values (1, 'hello backup world');
commit;
create table fxb.t (id number primary key, c varchar2(20 char));
insert into fxb.t values (1, 'from fxb');
commit;
create sequence fxa.s start with 1000 increment by 1;
declare n number; begin for i in 1 .. 5 loop n := fxa.s.nextval; end loop; end;
/
create or replace procedure fxa.p as begin null; end p;
/
create or replace function fxa.vpd_fn (p_schema in varchar2, p_object in varchar2) return varchar2 as begin return '1=1'; end vpd_fn;
/

prompt == grants received from another schema and from SYS, column grants
grant select, insert on fxb.t to fxa;
grant update (c) on fxb.t to fxa;
grant execute on sys.dbms_crypto to fxa;
grant execute on sys.dbms_lock to fxa;
grant execute on sys.utl_http to fxa;
-- @dblinter ignore(Core G-3145): the fixture view needs every column of the table
create or replace view fxa.v_other as select * from fxb.t;
grant select on fxa.t to fxb with grant option;
grant select on fxa.t to fx_role;
grant select on fxa.t to public;
create or replace procedure fxb.call_fxa as begin fxa.p; end call_fxa;
/
grant execute on fxa.p to fxb;
alter procedure fxb.call_fxa compile;

prompt == synonyms
create public synonym fx_t for fxa.t;
create public synonym fx_p for fxa.p;
create synonym fxb.fxa_t for fxa.t;

prompt == directory
create or replace directory fx_dir as '/opt/oracle/oradata/fx_dir';
grant read, write on directory fx_dir to fxa;

prompt == network ACL, credential, database links
begin
  sys.dbms_network_acl_admin.append_host_ace(host => 'example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('http'), principal_name => 'FXA', principal_type => sys.xs_acl.ptype_db));
end;
/
begin sys.dbms_credential.create_credential(credential_name => 'FXA.FX_CRED', username => 'u', password => 'p'); end;
/
create public database link fx_public_link using 'localhost:1521/FREEPDB1';

prompt == context, VPD, redaction
create or replace package fxa.ctx_pkg as procedure set_it; end ctx_pkg;
/
create or replace package body fxa.ctx_pkg as procedure set_it is begin sys.dbms_session.set_context('FX_CTX', 'K', 'V'); end set_it; end ctx_pkg;
/
create context fx_ctx using fxa.ctx_pkg;
create table fxa.t_vpd (id number, v varchar2(10 char));
insert into fxa.t_vpd values (1, 'a');
commit;
begin sys.dbms_rls.add_policy('FXA', 'T_VPD', 'FX_P1', 'FXA', 'VPD_FN', 'select'); end;
/
begin sys.dbms_rls.add_policy(object_schema => 'FXA', object_name => 'T_VPD', policy_name => 'FX_P2',
  function_schema => 'FXA', policy_function => 'VPD_FN', statement_types => 'select',
  sec_relevant_cols => 'V', sec_relevant_cols_opt => sys.dbms_rls.all_rows); end;
/
create table fxa.t_red (id number, secret varchar2(20 char));
insert into fxa.t_red values (1, 'topsecret');
commit;
begin sys.dbms_redact.add_policy(object_schema => 'FXA', object_name => 'T_RED', policy_name => 'FX_R1',
  column_name => 'SECRET', function_type => sys.dbms_redact.full, expression => '1=2'); end;
/

prompt == scheduler: jobs, program, schedule, class, job in another schema
begin sys.dbms_scheduler.create_job('FXA.J1', 'PLSQL_BLOCK', 'begin null; end;', repeat_interval => 'freq=daily', enabled => true); end;
/
begin sys.dbms_scheduler.create_program('FXA.PRG1', 'PLSQL_BLOCK', 'begin null; end;', enabled => true); end;
/
begin sys.dbms_scheduler.create_schedule('FXA.SCH1', repeat_interval => 'freq=hourly'); end;
/
prompt == Resource Manager: consumer group, plan, directives, mapping, switch grant
begin
  sys.dbms_resource_manager.clear_pending_area;
  sys.dbms_resource_manager.create_pending_area;
  sys.dbms_resource_manager.create_consumer_group(consumer_group => 'FX_GROUP', comment => 'fx group');
  sys.dbms_resource_manager.create_plan(plan => 'FX_PLAN', comment => 'fx plan');
  sys.dbms_resource_manager.create_plan_directive(plan => 'FX_PLAN', group_or_subplan => 'FX_GROUP', comment => 'fx',
    mgmt_p1 => 60, utilization_limit => 80, max_idle_time => 3600);
  sys.dbms_resource_manager.create_plan_directive(plan => 'FX_PLAN', group_or_subplan => 'OTHER_GROUPS', comment => 'rest',
    mgmt_p1 => 40);
  sys.dbms_resource_manager.set_consumer_group_mapping(attribute => 'ORACLE_USER', value => 'FXB', consumer_group => 'FX_GROUP');
  sys.dbms_resource_manager.validate_pending_area;
  sys.dbms_resource_manager.submit_pending_area;
exception when others then
  sys.dbms_resource_manager.clear_pending_area;
  raise;
end;
/
begin sys.dbms_resource_manager_privs.grant_switch_consumer_group('FXB', 'FX_GROUP', false); end;
/

prompt == job class with attributes, SYS schedule, windows, window group
begin sys.dbms_scheduler.create_job_class(job_class_name => 'FX_CLASS', resource_consumer_group => 'FX_GROUP',
  logging_level => sys.dbms_scheduler.logging_full, log_history => 7, comments => 'fx class'); end;
/
begin sys.dbms_scheduler.create_schedule(schedule_name => 'SYS.FX_WIN_SCHED', repeat_interval => 'freq=daily;byhour=3', comments => 'fx sched'); end;
/
begin sys.dbms_scheduler.create_window(window_name => 'FX_WIN', resource_plan => 'FX_PLAN',
  repeat_interval => 'freq=daily;byhour=22', duration => interval '2' hour, window_priority => 'LOW', comments => 'fx win'); end;
/
begin sys.dbms_scheduler.create_window(window_name => 'FX_WIN2', resource_plan => null,
  schedule_name => 'SYS.FX_WIN_SCHED', duration => interval '30' minute, comments => 'fx win2'); end;
/
begin sys.dbms_scheduler.disable('SYS.FX_WIN2'); end;
/
begin sys.dbms_scheduler.create_group(group_name => 'FX_WGRP', group_type => 'WINDOW', member => 'FX_WIN,FX_WIN2', comments => 'fx group'); end;
/
begin sys.dbms_scheduler.add_group_member(group_name => 'MAINTENANCE_WINDOW_GROUP', member => 'FX_WIN'); end;
/
begin sys.dbms_scheduler.create_job('FXA.J_WIN', program_name => 'FXA.PRG1', schedule_name => 'SYS.FX_WIN', enabled => false); end;
/

prompt == editions: an edition, a user that uses it, an object that exists only there
create edition fx_e1;
grant use on edition fx_e1 to fxb;
alter user fxb enable editions;
alter session set edition = fx_e1;
create or replace procedure fxb.p_ed as begin null; end p_ed;
/
alter session set edition = ora$base;

prompt == proxy user, a password role, default roles
alter user fxa grant connect through fxb;
create role fx_role2 identified by "Fx_Role_Pw1";
create role fx_role3;
grant fx_role3 to fxa;
grant fx_role2 to fxa;
alter user fxa default role all except fx_role2, fx_role3;

prompt == directory granted only to a role and to PUBLIC, external table, BFILE (files come from test-backup-fixtures.sh)
create or replace directory fx_dir2 as '/opt/oracle/oradata/fx_dir2';
grant read on directory fx_dir2 to fx_role;
grant read on directory fx_dir2 to public;
grant read on directory fx_dir to fxb;
create table fxa.ext_t (id number, name varchar2(20 char))
  organization external (type oracle_loader default directory fx_dir
    access parameters (records delimited by newline fields terminated by ',')
    location ('fx.csv'));
create table fxa.t_bfile (id number, f bfile);
insert into fxa.t_bfile values (1, bfilename('FX_DIR2', 'fx.txt'));
commit;

prompt == network: deny, role and PUBLIC entries, time limit, wallet entry
begin
  sys.dbms_network_acl_admin.append_host_ace(host => 'deny.example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('connect'), principal_name => 'FXB', principal_type => sys.xs_acl.ptype_db, granted => false));
  sys.dbms_network_acl_admin.append_host_ace(host => 'role.example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('http'), principal_name => 'FX_ROLE', principal_type => sys.xs_acl.ptype_db,
                       end_date => to_timestamp_tz('2099-01-01 00:00:00 +00:00', 'YYYY-MM-DD HH24:MI:SS TZH:TZM')));
  sys.dbms_network_acl_admin.append_host_ace(host => 'public.example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('resolve'), principal_name => 'PUBLIC', principal_type => sys.xs_acl.ptype_db));
  sys.dbms_network_acl_admin.append_wallet_ace(wallet_path => 'file:/opt/oracle/oradata/fx_wallet',
    ace => xs$ace_type(privilege_list => xs$name_list('use_client_certificates'), principal_name => 'FXA', principal_type => sys.xs_acl.ptype_db));
end;
/

prompt == public synonym over a database link
create public synonym fx_remote for fxa.t@fx_public_link;

prompt == assertions and a schema privilege (23.26)
-- @dblinter ignore(Core G-9208): the test compares these names with the backup
create assertion fxa.fx_assert check (not exists (select 1 from fxa.t where id < 0));
create assertion fxa.fx_assert2 check (not exists (select 1 from fxa.t where id < -5)) deferrable initially deferred;
grant select any table on schema fxb to fxa;

prompt == settings of a schema that create-user.sh makes (&env_user)
alter user &env_user profile fx_profile;
alter user &env_user quota 5m on tbs_fx;

prompt == SQL plan baseline and SQL Firewall (only reported, a backup cannot hold them)
grant administer sql management object to fxa;
grant select on sys.v_$sql to fxa;
-- test-backup-fixtures.sh runs SQL as FXB, then stops the capture and generates the allow list.
begin
  sys.dbms_sql_firewall.enable;
  sys.dbms_sql_firewall.create_capture(username => 'FXB', start_capture => true);
end;
/
begin sys.dbms_scheduler.create_job('FXB.J_FXA', 'PLSQL_BLOCK', 'begin fxa.p; end;', repeat_interval => 'freq=daily', enabled => true); end;
/
begin sys.dbms_scheduler.create_job('FXA.J_DISABLED', 'PLSQL_BLOCK', 'begin null; end;', repeat_interval => 'freq=daily', enabled => false); end;
/

prompt == AQ, MLE, domain, property graph, indexes
begin sys.dbms_aqadm.create_queue_table('FXA.QT', 'SYS.AQ$_JMS_TEXT_MESSAGE'); end;
/
begin sys.dbms_aqadm.create_queue('FXA.Q', 'FXA.QT'); sys.dbms_aqadm.start_queue('FXA.Q'); end;
/
create mle module fxa.m language javascript as
export function f() { return 1; }
/
create domain fxa.email_d as varchar2(200) constraint fx_email_chk check (email_d like '%@%');
create property graph fxa.g vertex tables (fxa.t key (id));
begin ctxsys.ctx_ddl.create_preference('FXA.FX_LEX', 'BASIC_LEXER'); end;
/
create index fxa.ti on fxa.docs (txt) indextype is ctxsys.context parameters ('lexer fxa.fx_lex');
create vector index fxa.vi on fxa.t (emb) organization neighbor partitions distance cosine;

prompt == unified audit policy
create audit policy fx_audit_pol actions select on fxa.t;

grant inherit privileges on user sys to apex_260200;
prompt == APEX workspace with a web credential, a workspace user and REST
begin
  apex_instance_admin.add_workspace(p_workspace => 'FXA', p_primary_schema => 'FXA');
  apex_util.set_workspace(p_workspace => 'FXA');
end;
/
begin
  apex_util.set_workspace(p_workspace => 'FXA');
  apex_util.create_user(p_user_name => 'FXUSER', p_web_password => 'Fx_Pw_12345c#', p_email_address => 'fx@example.com', p_developer_privs => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL');
end;
/
begin
  apex_util.set_workspace(p_workspace => 'FXA');
  apex_credential.create_credential(p_credential_name => 'FX Web Cred', p_credential_static_id => 'FX_WEB_CRED',
    p_authentication_type => apex_credential.c_type_basic, p_prompt_on_install => false);
  apex_credential.set_persistent_credentials(p_credential_static_id => 'FX_WEB_CRED', p_username => 'u', p_password => 'secret');
end;
/
begin apex_instance_admin.set_parameter('SMTP_HOST_ADDRESS', 'smtp.example.com'); end;
/
begin
  apex_util.set_workspace(p_workspace => 'FXA');
  apex_mail.send(p_to => 'fx@example.com', p_from => 'fx@example.com', p_subj => 'fx', p_body => 'fx');
end;
/

exit
