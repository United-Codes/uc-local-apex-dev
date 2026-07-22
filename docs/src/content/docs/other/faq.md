---
title: FAQ
description: Frequently Asked Questions about uc-local-apex-dev
sidebar:
    order: 1
---

## Why uc-local-apex-dev instead of other docker-compose files?

There are many docker-compose files available for running Oracle Database with APEX and ORDS. However, these two factors set uc-local-apex-dev apart:
- Upgrades: if new versions of APEX, ORDS or the DB are released, I provide migration guides to help you upgrade your environment.
- Scripts: This project includes many scripts to help you with common tasks like creating users, backing up the database, testing install scripts, etc. These scripts are designed to be easy to use and automate common development tasks.

## Can I modify ORDS settings?

Yes. A folder named `ords-config` will be created in the root directory. You can modify the config files there. The changes will be applied on the next restart of the ORDS container.

## How can I upgrade the database version?

We will release new versions of the project with migration guides when new ORDS or database versions are available. So make sure to keep an eye on the [GitHub repository](https://github.com/United-Codes/uc-local-apex-dev) for updates.

## How can I upgrade ORDS?

These will also be covered in the migration guides.

If you are experienced and don't want to wait you can modify the `docker-compose.yml` file to use a different ORDS version. You can find the available versions [in the Oracle container registry](https://container-registry.oracle.com/ords/ocr/ba/database/ords ).


## How can I patch APEX?

- You need a valid Oracle support account
- Go to the [APEX Downloads Page](https://www.oracle.com/tools/downloads/apex-downloads/)
- Click on Patch Set Bundle
- Login with your Oracle account and download the zip file
- Unzip the file
- Start a terminal in the directory
- Run the following command:

```sh
sql -name local-26ai-sys @catpatch.sql
```

To update the APEX images (assets):

```sh
# make sure you are in the directory of the unzipped patch directory

cp -r ./images/* {path_to_your_cloned_repo}/apex-images
```

## An APEX upgrade failed halfway. How do I retry it?

If an APEX version upgrade (`apexins.sql`) is interrupted, it can leave the
database in a half-upgraded state. Typical symptoms:

- `select version_no from apex_release;` still shows the **old** version, but
- `select comp_id, version, status from dba_registry where comp_id = 'APEX';`
  shows the **new** version with status `INVALID`, and
- there are many invalid objects in the new schema:
  `select owner, count(*) from dba_objects where status = 'INVALID' and owner like 'APEX%' group by owner;`

The good news: the previous APEX schema is left untouched during an upgrade, so
APEX usually keeps working on the old version while you recover. Retry like this
(example upgrades to the `APEX_260100` schema — adjust the schema name to the
version you are installing):

1. **Drop the partial new schema.** A plain re-run of `apexins.sql` fails with
   `Precondition for Phase 1 failed: APEX_260100 already exists`, so the
   half-built schema has to go first. APEX schemas are Oracle-maintained, so you
   need to enable migration mode to drop them:

   ```sh
   sql -name local-26ai-sys
   ```

   ```sql
   alter session set "_oracle_script" = true;
   drop user APEX_260100 cascade;
   exit;
   ```

2. **Re-run the install** from your existing `apex` folder (do not re-download —
   this keeps the version matching the schema you just dropped):

   ```sh
   cd apex
   sql -name local-26ai-sys @apexins.sql TBS_APEX TBS_APEX TEMP /i/
   cd ..
   ```

   This takes several minutes. When it finishes, verify:

   ```sql
   -- both should now show the new version, status VALID, 0 invalid objects
   select version_no from apex_release;
   select comp_id, version, status from dba_registry where comp_id = 'APEX';
   select count(*) from dba_objects where status = 'INVALID';
   ```

3. **Refresh the APEX images** so the static assets match the new version
   (a missing image folder shows up as `404` on `/i/...`):

   ```sh
   find ./apex-images -mindepth 1 -delete
   cp -R ./apex/images/. ./apex-images/
   ```
