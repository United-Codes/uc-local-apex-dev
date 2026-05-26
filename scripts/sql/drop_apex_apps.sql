declare
  e_no_workspace exception;
  pragma exception_init (e_no_workspace, -20987);
begin
  apex_application_install.set_workspace(user);
  apex_application_install.set_keep_sessions(false);


  for rec in (
    select application_id from apex_applications
  )
  loop
    dbms_output.put_line('Removing application ' || rec.application_id);
    apex_application_install.remove_application(rec.application_id);
  end loop;
exception
  when e_no_workspace
  then 
    sys.dbms_output.put_line ('No APEX Workspace with name: '||user);
end;
/
