---
title: Changelog
description: What changed in each release of uc-local-apex-dev
sidebar:
  order: 2
---

This page lists the changes of each release. Every entry links to its migration
guide. The release notes on GitHub hold the pull requests and the contributors.

## 26.5

[Migrate to 26.5](/products/uc-local-apex-dev/docs/migrations/26-5/)

### Purge jobs

- New script `scripts/create-purge-jobs.sh` (`local-26ai.sh create-purge-jobs`).
  It creates the jobs `UC_APEX_DEBUG_PURGE` and `UC_LOGGER_PURGE`. Each job keeps
  7 days of data. `after-first-db-start.sh` creates both jobs on a new install.
  `UC_LOGGER_PURGE` also shrinks the `LOGGER_LOGS` tables after the delete. Run
  `create-purge-jobs` again to update an existing job.

### Shrink space

- `shrink-space` rebuilds bloated tables. A delete does not lower the high-water mark of a table.
  A table with a segment of 50MB or more and live rows below half of the segment is bloated.
  The command lists these tables and asks before it rebuilds them. With `--auto`, it does not ask.
  It runs `alter table ... move online` and rebuilds the indexes online. Tables of Oracle-maintained
  schemas, partitioned tables, and tables with a domain or vector index stay as they are.

### Backup and restore

- New script `scripts/export-gaps.sh` (`local-26ai.sh export-gaps`). It shows what
  a schema export does not carry and writes `00_pre.sql` and `10_post.sql` with the roles, the
  grants beyond `create-user.sh`, and the public synonyms. `backup-all` runs it.
  `import-all` runs the SQL files.
- The SQL files also restore scheduler windows, Resource Manager plans, editions,
  proxy users, default roles, and wallet access entries. `export-gaps` copies the
  files of custom directories into the backup.
- The SQL files restore assertions and schema privileges (`grant ... on schema`).
  DataPump does not carry them. `export-gaps` writes the Select AI profiles to `ai_profiles.sql`.
- `export-gaps` lists what no backup holds: secrets, objects in other editions, SQL
  plan baselines, and SQL Firewall allow lists.
- `import-all` compares every object by name with the backup, not only the counts.
- `import-all` sets the vector memory of the old database and creates SQL domains
  whose DataPump DDL is broken. `rebuild` installs DBMS_CLOUD and utPLSQL if the
  old database had them.
- `backup-user` shows the tables whose rows DataPump skipped and adds them to
  `unrecoverable.txt`.
- `export-gaps` writes the SQL for Deep Data Security data roles, end users, and
  data grants. `import-all` runs it. End users come back locked with a random password.
  DataPump imports data grants, but they do not work. For this reason, the import
  leaves out the `XS_SECURITY` objects, and `10_post.sql` creates the data grants
  again. Related-table grants (`WHEN ... GRANTED ON`) are not restored.
- `backup-user` exports the ORDS definitions as `SYS`. A schema that is not in
  `.env` gets a temporary password only for the APEX export and the ORDS import.
- The backup and the import work for schema-only accounts (`no authentication`).
- New script `scripts/rebuild.sh` (`local-26ai.sh rebuild`). It runs a backup,
  deletes the database volume, installs a new database, and imports everything.
- `import-all` has the options `-y` and `-j N`. `-j N` runs the DataPump import of
  N schemas at the same time.
- `backup-user` and `import-backup` copy only the files of their own schema.
- `import-backup` skips a workspace that exists already. It tries failed
  applications again, and it removes a subscription to a master that is in no backup.
- `docker-compose.yml` reads the container name, the volume name, and the host ports
  from `.env`.

### JVM fix

- New script `scripts/fix-jvm.sh` (`local-26ai.sh fix-jvm`). It tests the
  in-database JVM and reloads it if it is broken.

### utPLSQL

- New script `scripts/install-utplsql.sh` (`local-26ai.sh install-utplsql`). It
  installs or upgrades utPLSQL in the schema `UTPLSQL`.

### Space report

- `used-space.sh` lists the 10 largest segments of every tablespace with 1GB or
  more of used space. It also lists the APEX file content per application.

## 26.4

[Migrate to 26.4](/products/uc-local-apex-dev/docs/migrations/26-4/)

### Versions

- DB 23.26.2.0 → 23.26.3.0. The datafiles are compatible, so no dump and restore
  is necessary. The data dictionary does not upgrade automatically.
- ORDS 26.1.2 → 26.2.2. ORDS upgrades its own schema on the first start.

### DBMS_CLOUD upgrade

- New script `scripts/upgrade-dbms-cloud.sh` (`local-26ai.sh upgrade-dbms-cloud`).
  A change of the database image does not upgrade `DBMS_CLOUD`. The script
  reloads the packages. It stops with an error if `DBMS_CLOUD` is not installed.

### Space management

- New script `scripts/cap-tablespaces.sh`. Every datafile gets a size ceiling, so
  one datafile alone cannot fill the 12GB limit of the Free edition. A PDB that
  passes the limit does not open, and you cannot correct it from inside.
- `create-user.sh` sets `MAXSIZE` on the tablespace of a new schema.
  `USER_TBS_MAXSIZE` in `.env` changes the default of `2G`.
- New script `scripts/compress-space.sh`. It applies Advanced Compression to the
  tables of one schema.
- `create-user.sh` gains `--compress`, which creates the schema with compression.
- `shrink-space.sh` reclaims `TBS_APEX` and the audit tablespace. It drops the
  old APEX version, shrinks the LOB segments, and resizes the datafiles.
- `after-first-db-start.sh` caps the undo datafile at 2048MB and `AUDIT_TRAIL` at
  1GB. It also creates the `UC_AUDIT_PURGE` job, which keeps 7 days of audit
  records.
- `used-space.sh` gains `--summary` and `--quiet`. It reports through the exit
  code, and the warning threshold moves from 10GB to 9.5GB.
- `stop.sh` shows a warning if the database is close to the limit. This is the
  last moment at which you can act.
- `drop-user.sh` reclaims the tablespace of the user and gains a `-y` flag.

### Podman

- The scripts detect the container engine now, so Podman works without changes.
  Earlier releases documented Podman, but the scripts called `docker` directly.
  The `CONTAINER_CLI` variable overrides the detected engine.
- CI installs the project with Docker and with Podman on every push.
- The project needs the Compose plugin. The old `docker-compose` and
  `podman-compose` commands are no longer supported.
- `install.sh` starts the database first and waits for it before it starts ORDS.
  Podman 5.5 and later do not report the container health status, so one
  `compose up -d` for the whole stack never continues.
- The Podman guide names the API socket and the `enable-linger` requirement.

### Secure mode

- New flag `install.sh --secure`. It sets `SECURE_MODE=true` in `.env`.
- Secure installs get bounded APEX session timeouts: 18 hours maximum length and
  8 hours maximum idle. Local installs keep the 7-day developer default.
- New variable `DEBUG_TO_SCREEN` in `.env` controls the debug output of ORDS.
  Release 26.3 passed `DEBUG` to the container, and that name collides with a
  variable of the ORDS image and stops it.

### APEX parameters

- The four parameters that APEX resolves at runtime are set once at the instance
  level. A workspace without its own override inherits the instance value.
- `upgrade-apex.sh` uses `APEX_INSTANCE_ADMIN.SET_PARAMETER` for the instance
  settings.

### Backups

- `backup-all.sh` resolves the workspace of a schema correctly. It deletes the
  Data Pump master tables that it creates, because they made every later dump
  larger. It reports a failure through the exit code.
- `import-datapump.sh` gains `-rt <old>=<new>`. The flag remaps the tablespaces
  of the dump. Without it, a dump from another database fails on every table
  with `ORA-00959`.
- `import-backup.sh` gives `-rs` and the new `-rt` to `import-datapump.sh`
  correctly. Earlier, `import-backup.sh <name> -rs <schema>` ignored the remap.

### Other scripts

- A new user gets the `create assertion` privilege, so the assertions of 23.26.1
  are usable.
- `after-first-db-start.sh` stops the passwords of the database accounts from
  expiring. `disable-password-expiration.sh` and `unexpire-accounts.sh` cover
  more accounts.
- `install-dbms-cloud.sh` completes the steps after the wallet.

### Documentation

- The documentation follows ASD-STE100 Simplified Technical English.
- New guide: expose the environment with HTTPS through an nginx reverse proxy.
- New guide: retry an APEX upgrade that failed.
- The installation guide is split, so a new user can start faster.

## Earlier releases

| Release | Headline | Migration guide |
| --- | --- | --- |
| [v26.3](https://github.com/United-Codes/uc-local-apex-dev/releases/tag/v26.3) | DB 23.26.2.0, ORDS 26.1.2, new `install.sh` and `upgrade-apex.sh` | [Migrate to 26.3](/products/uc-local-apex-dev/docs/migrations/26-3/) |
| [v26.2](https://github.com/United-Codes/uc-local-apex-dev/releases/tag/v26.2) | DB 26.1 and ORDS 26.1 | [Migrate to 26.2](/products/uc-local-apex-dev/docs/migrations/26-2/) |
| [v26.1](https://github.com/United-Codes/uc-local-apex-dev/releases/tag/v26.1) | Move to the 26ai database | [Migrate to 26.1](/products/uc-local-apex-dev/docs/migrations/26-1/) |
| [v25.3.1](https://github.com/United-Codes/uc-local-apex-dev/releases/tag/v25.3.1) | Hotfix for 25.3 | [Migrate to 25.3](/products/uc-local-apex-dev/docs/migrations/25-3/) |
| [v25.3](https://github.com/United-Codes/uc-local-apex-dev/releases/tag/v25.3) | DB 23.8 and ORDS 25.2 | [Migrate to 25.3](/products/uc-local-apex-dev/docs/migrations/25-3/) |
| [v25.1](https://github.com/United-Codes/uc-local-apex-dev/releases/tag/v25.1) | First public release | [Migrate to 25.1](/products/uc-local-apex-dev/docs/migrations/25-1/) |
