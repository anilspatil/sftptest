#!/bin/bash
source "${SCRIPT_DIR}/lib/common.sh"

# Ensures ssh-agent is running and has the required key loaded.
# This function is ONLY called when using key-based authentication.
ensure_ssh_agent_running_and_key_added() {
  log_enter_func

  # Start ssh-agent if it's not running for this session.
  if [ -z "$SSH_AUTH_SOCK" ]; then
    log_debug "ssh-agent not running, starting a new one."
    eval "$(ssh-agent -s)" >/dev/null 2>&1
  fi

  # Add the key to the agent if it's not already loaded.
  # This will prompt for a passphrase if one is set.
  if ! ssh-add -l | grep -qF "${SFTP_PRIVATE_KEY_PATH}"; then
    log_message "INFO" "Adding SSH key to agent: ${SFTP_PRIVATE_KEY_PATH}"
    ssh-add "${SFTP_PRIVATE_KEY_PATH}" || die "Failed to add SSH key to agent. Check key path and passphrase."
  else
    log_debug "SSH key already loaded in agent."
  fi

  log_exit_func
}