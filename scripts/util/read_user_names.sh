#!/usr/bin/env bash

# Anchor on a real identifier. drop-user.sh retires an entry by prefixing it
# with "# " and appending " # deleted", so a loose '^[^=]*_USER_PASSWORD' also
# matches "# MOVIES_USER_PASSWORD" -- which word-splits into the two junk names
# "#" and "MOVIES", and matches "#_UC_TESTINSTALL_USER_PASSWORD" whole. Both
# then reach SQLcl and fail. Same pattern import-all.sh already uses.
#
# Keep this bash 3.2 compatible: macOS ships /bin/bash 3.2, so no mapfile.
# Word splitting is safe here because the grep only yields [A-Z0-9_] names.
get_user_names() {
  local -a user_types
  # shellcheck disable=SC2207
  user_types=($(grep -oE '^[A-Z0-9_]+_USER_PASSWORD' ./.env | sed 's/_USER_PASSWORD//'))
  echo "${user_types[@]}"
}

# Usage example:
# read -a my_array <<< "$(get_user_names)"

# Then you can loop over my_array:
# for user in "${my_array[@]}"; do
#     echo "$user"
# done
