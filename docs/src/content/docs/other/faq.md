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
