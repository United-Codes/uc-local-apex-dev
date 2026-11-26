-- &env_user is the schema from .env that the fixtures changed. test-backup-fixtures.sh defines it.
whenever sqlerror continue
set feedback off
begin sys.dbms_redact.drop_policy('FXA', 'T_RED', 'FX_R1'); end;
/
begin sys.dbms_rls.drop_policy('FXA', 'T_VPD', 'FX_P1'); end;
/
begin sys.dbms_rls.drop_policy('FXA', 'T_VPD', 'FX_P2'); end;
/
begin apex_instance_admin.remove_workspace(p_workspace => 'FXA'); end;
/
begin ords_admin.enable_schema(p_enabled => false, p_schema => 'FXA'); end;
/
begin sys.dbms_scheduler.drop_job('FXA.J_WIN', true); end;
/
begin sys.dbms_scheduler.remove_group_member('MAINTENANCE_WINDOW_GROUP', 'FX_WIN'); end;
/
begin sys.dbms_scheduler.drop_group('FX_WGRP', true); end;
/
begin sys.dbms_scheduler.drop_window('FX_WIN', true); end;
/
begin sys.dbms_scheduler.drop_window('FX_WIN2', true); end;
/
begin sys.dbms_scheduler.drop_schedule('SYS.FX_WIN_SCHED', true); end;
/
begin sys.dbms_scheduler.drop_job_class('FX_CLASS', true); end;
/
begin
  sys.dbms_resource_manager.clear_pending_area;
  sys.dbms_resource_manager.create_pending_area;
  sys.dbms_resource_manager.delete_consumer_group_mapping(attribute => 'ORACLE_USER', value => 'FXB');
  sys.dbms_resource_manager.delete_plan('FX_PLAN');
  sys.dbms_resource_manager.submit_pending_area;
exception when others then
  sys.dbms_resource_manager.clear_pending_area;
  raise;
end;
/
begin
  sys.dbms_resource_manager.clear_pending_area;
  sys.dbms_resource_manager.create_pending_area;
  sys.dbms_resource_manager.delete_consumer_group('FX_GROUP');
  sys.dbms_resource_manager.submit_pending_area;
exception when others then
  sys.dbms_resource_manager.clear_pending_area;
  raise;
end;
/
begin
  <<baseline_loop>>
  for b in (select distinct sql_handle from dba_sql_plan_baselines where parsing_schema_name = 'FXA') loop
    if sys.dbms_spm.drop_sql_plan_baseline(sql_handle => b.sql_handle) >= 0 then null; end if;
  end loop baseline_loop;
end;
/
begin sys.dbms_sql_firewall.drop_allow_list('FXB'); end;
/
begin sys.dbms_sql_firewall.drop_capture('FXB'); end;
/
begin sys.dbms_sql_firewall.disable; end;
/
noaudit policy fx_audit_pol;
drop audit policy fx_audit_pol;
drop public synonym fx_t;
drop public synonym fx_p;
drop public synonym fx_remote;
drop public database link fx_public_link;
drop context fx_ctx;
drop directory fx_dir;
drop directory fx_dir2;
begin
  sys.dbms_network_acl_admin.remove_host_ace(host => 'example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('http'), principal_name => 'FXA', principal_type => sys.xs_acl.ptype_db));
  sys.dbms_network_acl_admin.remove_host_ace(host => 'deny.example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('connect'), principal_name => 'FXB', principal_type => sys.xs_acl.ptype_db, granted => false));
  sys.dbms_network_acl_admin.remove_host_ace(host => 'role.example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('http'), principal_name => 'FX_ROLE', principal_type => sys.xs_acl.ptype_db));
  sys.dbms_network_acl_admin.remove_host_ace(host => 'public.example.com',
    ace => xs$ace_type(privilege_list => xs$name_list('resolve'), principal_name => 'PUBLIC', principal_type => sys.xs_acl.ptype_db));
  sys.dbms_network_acl_admin.remove_wallet_ace(wallet_path => 'file:/opt/oracle/oradata/fx_wallet',
    ace => xs$ace_type(privilege_list => xs$name_list('use_client_certificates'), principal_name => 'FXA', principal_type => sys.xs_acl.ptype_db));
end;
/
begin sys.dbms_credential.drop_credential('FXA.FX_CRED', true); end;
/
alter user &env_user profile default;
alter user &env_user quota 0 on tbs_fx;
drop assertion fxa.fx_assert;
drop assertion fxa.fx_assert2;
drop user fxa cascade;
drop user fxb cascade;
drop edition fx_e1 cascade;
drop role fx_role;
drop role fx_role2;
drop role fx_role3;
drop profile fx_profile;
drop tablespace tbs_fx including contents and datafiles;
exit
