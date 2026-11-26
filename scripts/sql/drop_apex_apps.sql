-- @dblinter ignore(Core G-5010): this is a SQLcl script, dbms_output is its output
declare
  e_no_workspace exception;
  pragma exception_init (e_no_workspace, -20987);
begin
  apex_application_install.set_workspace(user);
  apex_application_install.set_keep_sessions(false);


  <<app_loop>>
  for rec in (
    select application_id from apex_applications
  )
  loop
    sys.dbms_output.put_line('Removing application ' || rec.application_id);
    apex_application_install.remove_application(rec.application_id);
  end loop app_loop;
exception
  when e_no_workspace
  then 
    sys.dbms_output.put_line ('No APEX Workspace with name: '||user);
end;
/
