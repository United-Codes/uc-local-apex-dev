#!/usr/bin/env bash

function get_ws_settings() {
  # Check if WORKSPACE is provided
  if [ -z "$1" ]; then
    echo "Error: Workspace parameter is required"
    return 1
  fi

  local WORKSPACE="$1"

  cat <<EOF
    APEX_INSTANCE_ADMIN.SET_WORKSPACE_PARAMETER (
        p_workspace   => '${WORKSPACE}',
        p_parameter   => 'MAX_SESSION_IDLE_SEC',
        p_value       => 604800
      );

      APEX_INSTANCE_ADMIN.SET_WORKSPACE_PARAMETER (
        p_workspace   => '${WORKSPACE}',
        p_parameter   => 'MAX_SESSION_LENGTH_SEC',
        p_value       => 604800
      );

      APEX_INSTANCE_ADMIN.SET_WORKSPACE_PARAMETER (
        p_workspace   => '${WORKSPACE}',
        p_parameter   => 'ACCOUNT_LIFETIME_DAYS',
        p_value       => 99999
      );

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

      APEX_INSTANCE_ADMIN.SET_WORKSPACE_PARAMETER (
        p_workspace   => '${WORKSPACE}',
        p_parameter   => 'MAX_WEBSERVICE_REQUESTS',
        p_value       => 100000
      );

      commit;
EOF
}
