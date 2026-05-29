#!/usr/bin/env bash

user_exists_in_db() {
  if [ -z "$1" ]; then
    echo "Usage: user_exists_in_db USERNAME"
    exit 1
  fi

  local USERNAME=$1
  local count
  count=$(
    sql -S -name "$DB_CONN_NAME" <<SQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM all_users WHERE username = UPPER('${USERNAME}');
EXIT;
SQL
  )

  # SQLcl output can include whitespace/banner lines or land on a stream we
  # don't capture (varies by SQLcl version and TERM); keep only the first
  # integer and default to 0 so the numeric test below never breaks.
  count=$(printf '%s' "$count" | grep -Eo '[0-9]+' | head -n1)
  count=${count:-0}

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
