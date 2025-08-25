#!/bin/bash
source "${SCRIPT_DIR}/lib/common.sh"

# Retries a command up to RETRY_COUNT times with a delay.
# Handles commands with multiple arguments correctly.
retry() {
  local attempt=1
  while [ $attempt -le "${RETRY_COUNT}" ]; do
    log_message "INFO" "Attempt ${attempt}/${RETRY_COUNT}: Running command: \"$@\""

    # The "$@" expansion is the key to correctly passing all arguments.
    "$@"

    local exit_code=$?
    if [ ${exit_code} -eq 0 ]; then
      return 0
    fi

    log_message "WARN" "Command failed with exit code ${exit_code}."

    if [ ${attempt} -lt "${RETRY_COUNT}" ]; then
      log_message "INFO" "Waiting ${RETRY_DELAY_SECONDS} seconds before retrying..."
      sleep "${RETRY_DELAY_SECONDS}"
    fi
    ((attempt++))
  done

  log_message "ERROR" "Command failed after ${RETRY_COUNT} attempts: \"$@\""
  return 1
}

# Creates a lock file to prevent concurrent runs.
acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "${LOCK_FILE_PATH}") 2> /dev/null; then
    log_message "WARN" "Script is already running. Lock file exists: ${LOCK_FILE_PATH}. Exiting."
    exit 99
  fi
  log_message "INFO" "Lock acquired. PID: $$. Lock file: ${LOCK_FILE_PATH}"
}

# Removes the lock file.
release_lock() {
  rm -f "${LOCK_FILE_PATH}"
  log_message "INFO" "Lock released."
}

# Sets a trap to ensure the cleanup function is always called on exit.
setup_trap() {
  trap 'cleanup $?' EXIT
}

# The main cleanup routine. Always releases the lock.
cleanup() {
  local exit_code=$1
  log_message "INFO" "Executing cleanup routine..."
  release_lock
  if [ ${exit_code} -ne 0 ] && [ ${exit_code} -ne 99 ]; then
    log_message "FATAL" "Script failed with exit code ${exit_code}."
  fi
  log_message "INFO" "Cleanup complete. Final exit code: ${exit_code}"
}

# Reads the content of the state file for the current job.
read_state_file() {
  if [ -f "${STATE_FILE}" ]; then
    cat "${STATE_FILE}"
  fi
}

# Appends a list of successfully processed filenames to the state file.
update_state_file() {
  # The parent run.sh script ensures this directory exists.
  cat >> "${STATE_FILE}"
}