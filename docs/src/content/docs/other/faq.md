---
title: FAQ
description: Frequently Asked Questions about uc-local-apex-dev
sidebar:
    order: 1
---

## Why uc-local-apex-dev instead of other docker-compose files?

Many docker-compose files for Oracle Database with APEX and ORDS are available. Two things make uc-local-apex-dev different:
- Upgrades: when a new version of APEX, ORDS, or the database comes out, I write a migration guide for it.
- Scripts: this project includes many scripts for common tasks. They create users, back up the database, and test install scripts. Each task is one command.

## Can I modify ORDS settings?

Yes. The installation creates an `ords-config` folder in the root directory. Change the configuration files in that folder. ORDS applies the changes at the next restart of the container.

## How can I upgrade the database version?

We release a new version of the project with a migration guide for every new ORDS or database version. Watch the [GitHub repository](https://github.com/United-Codes/uc-local-apex-dev) for these updates.

## How can I upgrade ORDS?

The migration guides also cover ORDS upgrades.

To upgrade before the next migration guide, change the ORDS version in the `docker-compose.yml` file. The [Oracle container registry](https://container-registry.oracle.com/ords/ocr/ba/database/ords ) lists the available versions.


## How can I patch APEX?

- You need a valid Oracle support account
- Go to the [APEX Downloads Page](https://www.oracle.com/tools/downloads/apex-downloads/)
- Click on Patch Set Bundle
- Log in with your Oracle account
- Download the zip file
- Unzip the file
- Start a terminal in the directory
- Run this command:

```sh
sql -name local-26ai-sys @catpatch.sql
```

To update the APEX images (the static assets), run this command:

```sh
# make sure you are in the directory of the unzipped patch directory

cp -r ./images/* {path_to_your_cloned_repo}/apex-images
```

## An APEX upgrade failed halfway. How do I retry it?

If an APEX upgrade (`apexins.sql`) stops in the middle, the database stays in a
half-upgraded state. These are the typical symptoms:

- `select version_no from apex_release;` still shows the **old** version, but
- `select comp_id, version, status from dba_registry where comp_id = 'APEX';`
  shows the **new** version with status `INVALID`, and
- there are many invalid objects in the new schema:
  `select owner, count(*) from dba_objects where status = 'INVALID' and owner like 'APEX%' group by owner;`

An upgrade does not change the previous APEX schema. APEX therefore continues to
work on the old version during the recovery.

Retry the upgrade with these steps. The example upgrades to the `APEX_260100`
schema. Use the schema name of the version that you install:

1. **Drop the partial new schema.** A new run of `apexins.sql` fails with
   `Precondition for Phase 1 failed: APEX_260100 already exists`. Drop the
   half-built schema first. Oracle maintains the APEX schemas, so you must
   enable migration mode to drop them:

   ```sh
   sql -name local-26ai-sys
   ```

   ```sql
   alter session set "_oracle_script" = true;
   drop user APEX_260100 cascade;
   exit;
   ```

2. **Run the install again** from your existing `apex` folder. Do not download
   APEX again. The version must match the schema that you dropped:

   ```sh
   cd apex
   sql -name local-26ai-sys @apexins.sql TBS_APEX TBS_APEX TEMP /i/
   cd ..
   ```

   This takes several minutes. At the end, make sure that the upgrade is complete:

   ```sql
   -- both should now show the new version, status VALID, 0 invalid objects
   select version_no from apex_release;
   select comp_id, version, status from dba_registry where comp_id = 'APEX';
   select count(*) from dba_objects where status = 'INVALID';
   ```

3. **Refresh the APEX images**, so the static assets match the new version. A
   missing image folder gives a `404` error on `/i/...`:

   ```sh
   find ./apex-images -mindepth 1 -delete
   cp -R ./apex/images/. ./apex-images/
   ```

## The database does not start and the log shows ORA-12954. What do I do?

The Free edition allows 12GB of datafiles in the PDB. If the PDB goes past this
limit, it does not open. The container reports that it is unhealthy, and ORDS
stops with `dependency failed to start`. The alert log shows this error:

```
FREEPDB1(3): ORA-12954: The request exceeds the maximum allowed database size of 12 GB.
```

The database checks the limit before it opens the PDB. `open read only` and
`open upgrade` therefore give the same error. No command inside the PDB can make
the PDB smaller, because you cannot get into it. The CDB itself opens, so only
the PDB is affected.

The usual cause is one datafile that grew without a ceiling. The undo datafile is
the first one to look at.

To prevent this failure, run `local-26ai.sh cap-tablespaces --apply` one time. See
[Common Tasks](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#limit-the-size-of-the-datafiles).

### Recover the database

CAUTION: Read all six steps before you start. Step 1 takes the datafile offline,
and the file stays offline until step 4 puts it back.

1. **Find the largest datafiles.** Start a shell in the database container:

   ```sh
   docker exec -it local-26ai sqlplus / as sysdba
   ```

   ```sql
   select round(sum(bytes)/1024/1024/1024, 2) pdb_gb from v$datafile where con_id = 3;
   select file#, round(bytes/1024/1024) mb, name from v$datafile
    where con_id = 3 order by bytes desc fetch first 5 rows only;
   ```

   Write down the file number and the path of the largest file. The steps below
   use file `14`, the undo datafile.

2. **Stop the database and mount the CDB.** A closed PDB accepts this one change
   only while the CDB is in mount state:

   ```sql
   shutdown immediate;
   startup mount;
   ```

3. **Take the datafile offline.** You must switch the session into the PDB first.
   From the root you get `ORA-01516`, and with the CDB open you get `ORA-01109`:

   ```sql
   alter session set container=FREEPDB1;
   alter database datafile '/opt/oracle/oradata/FREE/FREEPDB1/undotbs01.dbf' offline drop;
   ```

   An offline datafile counts as 0 bytes. The PDB is now under the limit. In
   `NOARCHIVELOG` mode, `offline drop` is the only form that works. The words
   "drop" here do not drop the tablespace.

4. **Open the database and put the file back.** The PDB opens because the file
   still counts as 0 bytes:

   ```sql
   alter database open;
   alter session set container=FREEPDB1;
   recover automatic datafile 14;
   alter database datafile 14 online;
   ```

   `ORA-00264: no recovery required` is the expected answer for a database that
   closed cleanly. The file is now online again.

5. **Make the file smaller.** CAUTION: Do this step now. The datafile counts with
   its full size again, so the PDB does not open if it stops before you finish:

   ```sql
   alter database datafile 14 resize 300M;
   alter database datafile 14 autoextend off;
   ```

   If you get `ORA-03297`, the file holds data above the size that you asked for.
   Use a larger size.

6. **Give the PDB a new undo tablespace.** Do this step only for an undo
   datafile. The old undo tablespace is small now, but it is also the active one:

   ```sql
   create undo tablespace UNDOTBS2
     datafile '/opt/oracle/oradata/FREE/FREEPDB1/undotbs02.dbf'
     size 200M autoextend on next 32M maxsize 2048M;
   alter system set undo_tablespace='UNDOTBS2' scope=both;
   exit;
   ```

Now restart the containers and make sure that the PDB is open:

```sh
./local-26ai.sh start
docker exec local-26ai bash -c "echo 'select name, open_mode from v\$pdbs;' | sqlplus -s / as sysdba"
```

`FREEPDB1` must show `READ WRITE`. Then give every datafile a ceiling, so this
failure does not come back:

```sh
./local-26ai.sh cap-tablespaces --apply
./local-26ai.sh shrink-space
```

## The installation stops at `Container local-26ai Waiting`. What do I do?

Update your copy of the repository. `install.sh` now starts the database alone,
waits for the ready banner in the log, and starts ORDS after that.

Podman is the cause. The ORDS service waits for the health status of the database
container. From Podman 5.5, Podman does not report this status over the
Docker-compatible socket that `podman compose` uses.

Podman 4.9.3 reported the status after 12 seconds. Podman 5.8.4 reports nothing.
Podman also reports no unhealthy status, so compose has no failure to show. The
command therefore does not stop. Docker does not have this problem.

`./local-26ai.sh start` uses one `up -d` command for all services, so it stops at
the same line. To start the stack by hand, use two steps. First start the
database:

```sh
podman compose up -d 26ai
podman compose logs -f 26ai
```

The log shows `DATABASE IS READY TO USE`. Press `Ctrl+C` and start ORDS:

```sh
podman compose up -d --no-deps ords-26ai
```

`--no-deps` stops compose from reading the health status. The database is already
open at this point, so the health gate has no more purpose.
