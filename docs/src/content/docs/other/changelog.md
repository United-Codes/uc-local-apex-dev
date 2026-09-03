---
title: Changelog
description: What changed in each release of uc-local-apex-dev
sidebar:
  order: 2
---

This page lists the changes of each release. Every entry links to its migration
guide. The release notes on GitHub hold the pull requests and the contributors.

## 26.4 (not released)

[Migrate to 26.4](/products/uc-local-apex-dev/docs/migrations/26-4/)

### Versions

- DB 23.26.2.0 → 23.26.3.0. The datafiles are compatible, so no dump and restore
  is necessary. The data dictionary needs one repair command.
- ORDS 26.1.2 → 26.2.2. ORDS upgrades its own schema on the first start.

### Data dictionary repair

- New script `scripts/repair-ru-dictionary.sh`. A change of the database image
  does not upgrade the data dictionary. The script finds the dictionary views
  that are missing and reloads the catalog scripts that create them. It also
  reloads the in-database JVM, which the image change breaks in silence.
- `--check` shows the gap. `--repair` closes it. `--summary` gives `key=value`
  lines for CI.
- The repair covers every release update that your database missed. One run is
  enough.
- New CI workflow `test-db-upgrade.yml`. It installs the current version, changes
  the image on the same datafiles, and makes sure that the data and APEX stay
  unchanged.

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

- Podman works natively. CI tests Docker and Podman on every push.
- `install.sh` starts the database first, waits for it, and starts the other
  services after that. Podman 5.5 and later do not report the container health
  status, so a plain `compose up -d` never continues.
- The database healthcheck works under Podman.
- The project needs the Compose plugin. Support for the old `docker-compose` and
  `podman-compose` commands is gone.
- `install.sh` creates the bind-mount directories before it calls `compose up`.
- The documentation names the Podman socket and the `enable-linger` requirement.

### Secure mode

- New flag `install.sh --secure`. It sets `SECURE_MODE=true` in `.env`.
- Secure installs get bounded APEX session timeouts: 18 hours maximum length and
  8 hours maximum idle. Local installs keep the 7-day developer default.
- The ORDS debug flag is now `DEBUG_TO_SCREEN`. The old name collided with a
  variable of the ORDS image and stopped the container.

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

- A new user gets the `create assertion` privilege.
- The passwords of the database accounts do not expire.
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
