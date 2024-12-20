#!/usr/bin/env bash

user_exists_in_db() {
  if [ -z "$1" ]; then
    echo "Usage: user_exists_in_db USERNAME"
    exit 1
  fi

  local USERNAME=$1
  local count=$(
    sql -S -name $DB_CONN_NAME <<SQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM all_users WHERE username = UPPER('${USERNAME}');
EXIT;
SQL
  )

  if [ "$count" -gt 0 ]; then
    return 0 # true in bash
  else
    return 1 # false in bash
  fi
}

# Usage example:
# if user_exists_in_db "someuser"; then
#     echo "User exists in database"
# else
#     echo "User does not exist in database"
# fi
