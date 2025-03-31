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

end;
/
