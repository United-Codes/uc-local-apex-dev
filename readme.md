# Oracle APEX Docker

## APEX

URL: http://localhost:8181/ords/apex
Username: admin
Password: Welcome_1

### Adding new workspace

This command will create a new db schema and workspace. You can access the workspace with both the username `ADMIN` or the given schema name and the password `Welcome_1`.

``` sh
./scripts/create-user.sh movies
```

## Delete database data

```sh
docker stop apex-24-1-23ai
docker rm apex-24-1-23ai
docker volume rm oradata
```


## Troubleshooting

### ORA-01157

ORA-01157: cannot identify/lock data file 20 - see DBWR trace file
ORA-01110: data file 20: '/opt/oracle/product/23ai/dbhomeFree/dbs/tbs_test.dat'

**I have no idea how to fix this.**

Attempt:

```
docker run -it \
  -v ./oradata:/opt/oracle/oradata \
  --entrypoint /bin/bash \
  -p 1521:1521 \
  --env-file ./.env \
  --rm \
  gvenzl/oracle-free:23.5-full

> sqlplus / as sysdba
> alter database open;
> STARTUP NOMOUNT;
> ALTER DATABASE MOUNT;
> ALTER SYSTEM CHECK DATAFILES;
> ALTER DATABASE OPEN;
# ERROR at line 1:
# ORA-01157: cannot identify/lock data file 20 - see DBWR trace file
# ORA-01110: data file 20: '/opt/oracle/product/23ai/dbhomeFree/dbs/tbs_test.dat'
# Help: https://docs.oracle.com/error-help/db/ora-01157/
> exit

# check if file actually exists
> ls -l /opt/oracle/product/23ai/dbhomeFree/dbs/tbs_test.dat
ls: cannot access '/opt/oracle/product/23ai/dbhomeFree/dbs/tbs_test.dat': No such file or directory

# remove the file from the database
> sqlplus / as sysdba
> ALTER DATABASE DATAFILE '/opt/oracle/product/23ai/dbhomeFree/dbs/tbs_test.dat' OFFLINE DROP;
# ERROR at line 1:
# ORA-01516: nonexistent log file, data file, or temporary file
# "/opt/oracle/product/23ai/dbhomeFree/dbs/tbs_test.dat" in the current container
# Help: https://docs.oracle.com/error-help/db/ora-01516/

> alter tablespace tbs_test offline;
# doesn't work
> ALTER DATABASE DATAFILE 20 OFFLINE;
# doesn't work
```
