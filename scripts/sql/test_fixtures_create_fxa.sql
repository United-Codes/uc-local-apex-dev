-- Fixtures that only the schema owner can create. test-backup-fixtures.sh runs
-- this file connected as FXA, after test_fixtures_create.sql.
whenever sqlerror continue
set define off echo off feedback off

prompt == private database link
create database link fx_link connect to fxa identified by "Fx_Pw_12345a#" using 'localhost:1521/FREEPDB1';

prompt == ORDS: schema enable, auto-REST object, module, template, handler
begin
  ords.enable_schema(p_enabled => true, p_url_mapping_type => 'BASE_PATH', p_url_mapping_pattern => 'fxapi', p_auto_rest_auth => false);
  ords.enable_object(p_enabled => true, p_object => 'T', p_object_type => 'TABLE', p_object_alias => 'fxt');
  ords.define_module(p_module_name => 'fxmod', p_base_path => '/fxmod/', p_items_per_page => 25, p_status => 'PUBLISHED');
  ords.define_template(p_module_name => 'fxmod', p_pattern => 'hello');
  ords.define_handler(p_module_name => 'fxmod', p_pattern => 'hello', p_method => 'GET',
    p_source_type => ords.source_type_collection_feed, p_source => 'select * from fxa.t');
  commit;
end;
/

prompt == SQL plan baseline of FXA
select /* fx_spm_marker */ count(*) from t where id > 0;
declare
  n pls_integer;
begin
  for c in (select sql_id from v$sql where sql_text like 'select /* fx_spm_marker */%' and parsing_schema_name = 'FXA') loop
    n := dbms_spm.load_plans_from_cursor_cache(sql_id => c.sql_id);
  end loop;
end;
/
exit
