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
