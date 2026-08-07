#!/usr/bin/env bash

function get_ws_settings() {
  # Check if WORKSPACE is provided
  if [ -z "$1" ]; then
    echo "Error: Workspace parameter is required"
    return 1
  fi

  local WORKSPACE="$1"

  # Only parameters that genuinely need a per-workspace value belong here. The
  # true runtime-cascade parameters we used to set here -- MAX_SESSION_IDLE_SEC,
  # MAX_SESSION_LENGTH_SEC, ACCOUNT_LIFETIME_DAYS, MAX_WEBSERVICE_REQUESTS -- are
  # nullable per workspace and resolve to the instance-level value at runtime, so
  # we set them once at the instance level (see scripts/upgrade-apex.sh) and drop
  # them here.
  #
  # The two that remain are NOT interchangeable with instance settings:
  #  - WORKSPACE_EMAIL_MAXIMUM has no instance-level equivalent.
  #  - ALLOW_HOSTING_EXTENSIONS is a NOT NULL per-workspace column (it cannot be
  #    cleared to inherit), so a freshly created workspace falls back to the 'N'
  #    column default unless we set it explicitly here.
  cat <<EOF
    APEX_INSTANCE_ADMIN.SET_WORKSPACE_PARAMETER (
        p_workspace   => '${WORKSPACE}',
        p_parameter   => 'ALLOW_HOSTING_EXTENSIONS',
        p_value       => 'Y'
      );

      APEX_INSTANCE_ADMIN.SET_WORKSPACE_PARAMETER (
        p_workspace   => '${WORKSPACE}',
        p_parameter   => 'WORKSPACE_EMAIL_MAXIMUM',
        p_value       => 100000
      );

      commit;
EOF
}
