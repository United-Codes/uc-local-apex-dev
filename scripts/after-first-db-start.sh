#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

# save sys connection
./scripts/util/save-sqlcl-connection.sh

# setup datapump directories
./scripts/util/create-datapump-directory.sh

./scripts/sync-backups-folder.sh
