---
title: Changelog
description: What changed in each release of uc-local-apex-dev
sidebar:
  order: 2
---

This page lists the changes of each release. Every entry links to its migration
guide. The release notes on GitHub hold the pull requests and the contributors.

## 26.4

[Migrate to 26.4](/products/uc-local-apex-dev/docs/migrations/26-4/)

### Versions

- DB 23.26.2.0 → 23.26.3.0. The datafiles are compatible, so no dump and restore
  is necessary. The data dictionary needs one repair command.
- ORDS 26.1.2 → 26.2.2. ORDS upgrades its own schema on the first start.

### Data dictionary repair

- New script `scripts/repair-ru-dictionary.sh`
  (`local-26ai.sh repair-ru-dictionary`). A change of the database image does not
  upgrade the data dictionary. The database keeps the dictionary of the release
  update that created it, and the in-database JVM stops working without a
  message. The script finds the dictionary views that are missing, reloads the
  catalog scripts that create them, and reloads the JVM.
- `--check` shows the gap. `--repair` closes it. `--summary` gives `key=value`
  lines for CI.
- One run repairs every release update that your database missed, not only the
  newest one.
- `test-db-upgrade.yml` now also proves the repair. The workflow changes the
  image on the same datafiles, runs the repair, and makes sure that the data,
  APEX and the dictionary are complete after it.

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
