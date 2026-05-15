---
title: Upgrade APEX
description: Guide on how to upgrade any APEX version in the containerized UC Local APEX Dev
sidebar:
  order: 1
---

You don't depend on any changes to this project to upgrade APEX. As soon as an update is available, you can follow these steps to upgrade APEX in your local environment.

## Versions >= 26.2: use the upgrade script

Starting with version 26.2, this project ships a `scripts/upgrade-apex.sh` script that automates downloading the latest APEX, running the installer, copying the images, and reapplying the `INTERNAL` workspace settings (extended session timeout, ACLs, etc.).

```sh
./scripts/upgrade-apex.sh
```

## Versions < 26.2: manual upgrade

### Download and unzip latest APEX version

```sh
wget https://download.oracle.com/otn_software/apex/apex-latest.zip
unzip apex-latest.zip
rm apex-latest.zip
rm -rf ./META-INF || true
```

### Perform the upgrade

```sh
cd apex
sql -name local-23ai-sys @apexins.sql TBS_APEX TBS_APEX TEMP /i/
exit;
```

(If you are still on 23ai use `SYSAUX` instead)

```sh
cd apex
sql -name local-23ai-sys @apexins.sql SYSAUX SYSAUX TEMP /i/
exit;
```

### Update the images

```sh
cd ..
rm -rf ./apex-images || true
cp -r ./apex/images ./apex-images
```

If you get a popup error saying your files are outdated, you need to clear your browser cache.
