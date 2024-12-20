#!/usr/bin/env bash

get_user_names() {
  local -a user_types
  user_types=($(grep -o '^[^=]*_USER_PASSWORD' ./.env | sed 's/_USER_PASSWORD//'))
  echo "${user_types[@]}"
}

# Usage example:
# read -a my_array <<< "$(get_user_names)"

# Then you can loop over my_array:
# for user in "${my_array[@]}"; do
#     echo "$user"
# done
