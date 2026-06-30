---
title: Common Tasks
description: Learn how to perform common development tasks with UC Local APEX Dev
sidebar:
  order: 2
---

import { Aside } from "@astrojs/starlight/components";

Once your environment is set up, these are the most common tasks you'll perform during APEX development.

<Aside type="note" title="Docker or Podman">
The commands below that call `docker compose` work with Podman too — just substitute `podman compose`. The project's own scripts (`local-26ai.sh`, `./scripts/*.sh`) auto-detect the engine, so you don't need to change anything when running those.
</Aside>

## Managing Containers

### Start/Stop Containers

```bash
# Stop database
local-26ai.sh stop
# You could also run this, but the script will gracefully stop the database
# docker compose stop   (or: podman compose stop)

local-26ai.sh start
# Or
# docker compose start  (or: podman compose start)
```

## ORDS Configuration

### Modify ORDS Settings

The `ords-config` folder in the root directory contains ORDS configuration files. Modify these files and restart the ORDS container to apply changes:

```bash
# After modifying config files
docker compose restart ords-26ai   # or: podman compose restart ords-26ai
```

### SSL Configuration

Enable HTTPS for ORDS by creating self-signed certificates. On MacOS and Linux it will also add the certificate to your system's keychain:

```bash
sudo ./scripts/create-self-signed-certificates.sh
docker compose restart ords-26ai   # or: podman compose restart ords-26ai
```

Access via: https://localhost:8443/ords (Port 8443 instead of 8181).

## Maintenance Tasks

### Check Database Space Usage

Keep in mind that the FREE database has a space limitation of 12GB. You can check the used space with:

```bash
local-26ai.sh used-space

#    CURRENT_GB    LIMIT_GB    PERCENT_OF_LIMIT STATUS
# _____________ ___________ ___________________ _________
#          5.04          12               41.97 OK


# Tablespace                 Total MB    Used MB    Free MB    Pct. Free
# _______________________ ___________ __________ __________ ____________
# SYSAUX                         3440       3158        282            8
# SYSTEM                          690        679         11            2
# USERS                           118         59         59           50
# TBS_PLUGINS                     112         38         74           66
# UNDOTBS1                        103         23         80           78
# TBS_AOP                          77          7         70           91
```

### Shrink Database Files

If your tablespaces have grown larger than the space they actually use, you can shrink them to reclaim space. This can take a while.

```bash
local-26ai.sh shrink-space
```

### Compress a Schema's Tablespace

While `shrink-space` only reclaims *unused* space, `compress-space` makes the data itself smaller. It enables [Advanced Compression](https://www.oracle.com/database/advanced-compression/) (included in Oracle Database Free) on a single schema's `tbs_<schema>` tablespace and rebuilds its existing objects so they're stored compressed:

- Tables get advanced row compression (`COMPRESS FOR OLTP`), which keeps recompressing as rows change.
- B-tree indexes get advanced index compression (`COMPRESS ADVANCED LOW`).
- New segments inherit the compression automatically, because the tablespace defaults are set too.

After rebuilding, it runs `dbms_space.shrink_tablespace` and resizes the datafile down, so the freed space is returned to the OS in the same run.

```bash
local-26ai.sh compress-space movies
# Skip the confirmation prompt with -y:
local-26ai.sh compress-space movies -y

# Tablespace usage before compression:
#    USED_MB    ALLOCATED_MB
# __________ _______________
#     1000.8            2100
# ...
# Tablespace usage after compression:
#    USED_MB    ALLOCATED_MB
# __________ _______________
#      595.6           749.7
```

<Aside type="note">
The operation is online and non-destructive (objects are rebuilt, never dropped) and safe to re-run — already-compressed objects are skipped. Single-column unique/primary-key indexes are intentionally left uncompressed: advanced index compression can't dedup them, so there's nothing to gain.
</Aside>

### Disable Archive Logs

For development environments, you might want to disable archive logging. You will be asked if you want to do this in the `after-first-db-start.sh` script, but you can also run it manually:

```bash
./scripts/disable-archive-logs.sh
```

### Manage APEX Account Expiration

#### Unexpire Accounts

If APEX_PUBLIC_USER or workspace accounts are locked due to password expiration, unlock them with:

```bash
./scripts/unexpire-accounts.sh
```

This is useful after database migrations or when accounts have expired due to time constraints.

#### Disable Password Expiration

To prevent APEX workspace accounts from expiring in the future:

```bash
./scripts/disable-password-expiration.sh
```

<Aside type="note">
  Even with password expiration disabled, users may still be prompted to change
  their password on their first login after a migration.
</Aside>

## Workspace Import/Export

### Import All Exports

Automatically import all export files from the `./backups/import/` directory:

```bash
./scripts/import-all.sh
```

This is particularly useful during database migrations when you need to bulk import multiple workspaces and schemas. The script will provide a summary of successful and failed imports.

### Fix Workspace Export Issues

When re-importing APEX workspaces, you may encounter issues due to a [known bug with group assignments](https://forums.oracle.com/ords/apexds/post/apex-18-2-failing-to-import-workspace-5048). Fix this automatically:

```bash
./scripts/fix-ws-group-ids.sh
```

This script updates all export files in `./backups/import/` to remove problematic group ID parameters, allowing successful re-import.

## Complete Environment Reset

### Delete All Data

To start completely fresh (⚠️ **ALL DATA WILL BE LOST**):

```bash
docker compose down        # or: podman compose down
docker volume rm oradata-26ai   # or: podman volume rm oradata-26ai
rm .env
```

Then follow the [setup instructions](/products/uc-local-apex-dev/docs/getting-started/) again.
