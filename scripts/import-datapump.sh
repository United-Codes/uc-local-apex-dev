#!/usr/bin/env bash
# desc: Import a DataPump dump for a schema (-rs remaps to a different schema name)

set -e

source ./scripts/util/load_env.sh

# check parameter is passed
if [ -z "$1" ]; then
  echo "Usage: $0 <schema_name> [-rs <remap_schema_name>]"
  exit 1
fi

USERNAME=$1
USERNAME_LOWER=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')
SQLCRED_NAME="${DB_CONN_BASE}-${USERNAME_LOWER}"

# Parse optional -rs parameter
REMAP_SCHEMA=""
SCHEMA_NAME="${USERNAME_LOWER}"
if [ "$2" = "-rs" ] && [ -n "$3" ]; then
  REMAP_SCHEMA_NAME=$(echo "$3" | tr '[:upper:]' '[:lower:]')
  # -objectid FALSE only when remapping. DataPump replays the exported OID of an
  # object TYPE, which the target database already holds under the old schema,
  # so the type fails with ORA-02304 / ORA-39083 and every dependent object goes
  # with it. A new OID is fine for a restore. Leave the default alone for a
  # same-name restore so that path stays byte-identical to before.
  REMAP_SCHEMA="-remapschemas ${REMAP_SCHEMA_NAME}=${USERNAME_LOWER} -objectid FALSE"
  SCHEMA_NAME="${REMAP_SCHEMA_NAME}"
fi

# SQLcl hardcodes KEEP_MASTER=1, so the ISQL_<n> master table survives the job
# and there is no switch to stop it (see scripts/sql/drop_dp_tables.sql). Drop it
# from a trap so an import that dies half way does not leave one behind.
drop_dp_master_tables() {
  sql -name "$SQLCRED_NAME" <<'SQL' || true
    set serveroutput on size unlimited
    @./scripts/sql/drop_dp_tables.sql
    exit;
SQL
}
trap drop_dp_master_tables EXIT

# See backup-user.sh: the first `datapump` command of an SQLcl session always
# fails with "Value DATA_PUMP_DIR is not valid for Parameter directory". Absorb
# it with a `-noexec TRUE` dry run instead of writing the import out twice.
#
# `-version latest` is not cosmetic. DataPump silently drops whole object types
# that the requested metadata version cannot represent, and the job still
# reports success. Measured on 23.26.2 with -version 11.0.0: MLE_MODULE,
# SQL_DOMAIN, DOMAIN_ASSOCIATION, IDENTITY_COLUMN and VECTOR_INDEX all vanished
# without an error. Never lower this, and never let it fall back to the SQLcl
# default of COMPATIBLE.
sql -name "$SQLCRED_NAME" <<SQL
  select user from dual;

  prompt == SQLcl warm-up. The next "DATA_PUMP_DIR is not valid" message is
  prompt == expected and harmless. The real import follows it.
  datapump import -noexec TRUE

  prompt == Importing ${USERNAME_LOWER}.dmp
  datapump import -
  -schemas ${SCHEMA_NAME} -
  -directory datapump_import_dir -
  -dumpfile ${USERNAME_LOWER}.dmp -
  -logfile ${USERNAME_LOWER}.log -
  -version latest ${REMAP_SCHEMA}

  commit;

  exit;
SQL
