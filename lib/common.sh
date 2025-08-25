#!/bin/bash

# Escapes special characters for safe inclusion in a JSON string.
escape_json_string() {
  echo "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\//\\\//g' -e 's/\b/\\b/g' -e 's/\f/\\f/g' -e 's/\n/\\n/g' -e 's/\r/\\r/g' -e 's/\t/\\t/g'
}

# Central logging function. Handles text and JSON formats.
log_message() {
  local level="$1"
  local message="$2"

  # Ensure the log directory exists
  if [ -n "${LOG_FILE_PATH}" ]; then
    mkdir -p "$(dirname "${LOG_FILE_PATH}")"
  fi

  local log_line
  if [ "${LOG_FORMAT}" = "json" ]; then
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local escaped_message
    escaped_message=$(escape_json_string "$message")
    log_line="{\"timestamp\":\"${timestamp}\", \"level\":\"${level}\", \"message\":\"${escaped_message}\", \"job_id\":\"${JOB_ID}\", \"sftp_host\":\"${SFTP_HOST}\", \"pid\":${$}}"
  else
    log_line="$(date '+%Y-%m-%d %H:%M:%S') [${level}] - ${message}"
  fi

  # Append to the log file unconditionally.
  echo "${log_line}" >> "${LOG_FILE_PATH:-/dev/null}"

  # Conditionally write to STDERR for console visibility.
  # This prevents log messages from contaminating stdout captures.
  if [[ "$level" != "DEBUG" || "$VERBOSE_MODE" = true ]]; then
    echo -e "${log_line}" >&2
  fi
}

# Helper for verbose/debug messages. Only prints if --verbose is set.
log_debug() {
  if [[ "$VERBOSE_MODE" = true ]]; then
    log_message "DEBUG" "$1"
  fi
}

# Helper to trace when a function is entered.
log_enter_func() {
  # FUNCNAME[1] is the name of the function that called this one
  log_debug "Entering: ${FUNCNAME[1]}"
}

# Helper to trace when a function exits.
log_exit_func() {
  log_debug "Exiting: ${FUNCNAME[1]}"
}

# Logs a fatal error and exits the script immediately.
die() {
  log_message "FATAL" "$1"
  exit 1
}