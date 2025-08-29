#!/bin/bash
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# ==============================================================================
# USAGE / HELP FUNCTION
# ==============================================================================
usage() {
  cat <<EOM
Generic SFTP to GCS Sync Script (Enterprise Edition)

USAGE:
  ./run.sh [REQUIRED OPTIONS] [AUTHENTICATION OPTIONS] [OTHER OPTIONS]

REQUIRED OPTIONS:
  -h, --sftp-host HOST          SFTP server hostname or IP address.
  -u, --sftp-user USER          SFTP username.
  -r, --sftp-remote-path PATH   Remote source directory on the SFTP server.
  -b, --gcs-bucket BUCKET       The destination GCS bucket name.

AUTHENTICATION OPTIONS (Priority: Secret > File > Env Var > Key):
      --sftp-secret-id ID       [RECOMMENDED] Fetch password from Google Secret Manager.
                                REQUIRES --gcp-project-id.
      --gcp-project-id ID       The GCP Project ID where the secret is stored.
                                REQUIRED when using --sftp-secret-id.
  -k, --sftp-key PATH           Use a specific SSH private key (Default: ~/.ssh/id_rsa).
  --sftp-password-file FILE     (Legacy) Use a local file containing the password.
  --sftp-password-env VAR       (Legacy) Use an environment variable with the password.

OPTIONAL OPTIONS:
  -p, --sftp-port PORT          SFTP server port (Default: 22).
  -g, --gcs-path PATH           Destination path within the GCS bucket (Default: root).
  -w, --workflow MODE           'batch' or 'streaming' (Default: batch).
  -f, --file-pattern PATTERN    Pattern to match files in the SFTP directory (e.g., "*.csv").
                                (Default: "*").
      --batch-size N            Number of files to process per chunk (Default: 100).
      --log-format FORMAT       Log output format: 'text' or 'json' (Default: text).
      --delete-remote           Enable deletion of files from SFTP after successful transfer.
      --verbose                 Enable detailed debug logging for troubleshooting.
      --help                    Display this help message and exit.
EOM
  exit 1
}

# ==============================================================================
# ARGUMENT & PROFILE PARSING
# ==============================================================================

# Source defaults first
source "${SCRIPT_DIR}/config.sh"

# --- Set default values ---
SFTP_PORT="22"
SFTP_PRIVATE_KEY_PATH="${HOME}/.ssh/id_rsa"
GCS_DESTINATION_PATH=""
WORKFLOW="batch"
DELETE_REMOTE_AFTER_SUCCESS=false
DELETE_LOCAL_AFTER_SUCCESS=true
LOG_FORMAT="text"
SFTP_SECRET_ID=""
GCP_PROJECT_ID=""
SFTP_PASSWORD_FILE=""
SFTP_PASSWORD_ENV_VAR=""
SFTP_PASSWORD=""
VERBOSE_MODE=false
SFTP_FILE_PATTERN="*"

# --- Parse command-line arguments ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--sftp-host)         SFTP_HOST="$2"; shift ;;
    -p|--sftp-port)         SFTP_PORT="$2"; shift ;;
    -u|--sftp-user)         SFTP_USER="$2"; shift ;;
    -k|--sftp-key)          SFTP_PRIVATE_KEY_PATH="$2"; shift ;;
    -r|--sftp-remote-path)  SFTP_REMOTE_PATH="$2"; shift ;;
    -b|--gcs-bucket)        GCS_BUCKET_NAME="$2"; shift ;;
    -g|--gcs-path)          GCS_DESTINATION_PATH="$2"; shift ;;
    -w|--workflow)          WORKFLOW="$2"; shift ;;
    -f|--file-pattern)      SFTP_FILE_PATTERN="$2"; shift ;;
    --sftp-secret-id)       SFTP_SECRET_ID="$2"; shift ;;
    --gcp-project-id)       GCP_PROJECT_ID="$2"; shift ;;
    --sftp-password-file)   SFTP_PASSWORD_FILE="$2"; shift ;;
    --sftp-password-env)    SFTP_PASSWORD_ENV_VAR="$2"; shift ;;
    --batch-size)           BATCH_SIZE="$2"; shift ;;
    --log-format)           LOG_FORMAT="$2"; shift ;;
    --delete-remote)        DELETE_REMOTE_AFTER_SUCCESS=true ;;
    --verbose)              VERBOSE_MODE=true ;;
    --help)                 usage ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac; shift
done

# ==============================================================================
# VALIDATION AND ENVIRONMENT SETUP
# ==============================================================================

# --- Validate required arguments ---
if [ -z "$SFTP_HOST" ] || [ -z "$SFTP_USER" ] || [ -z "$SFTP_REMOTE_PATH" ] || [ -z "$GCS_BUCKET_NAME" ]; then
  echo "Error: Missing one or more required options."; echo ""; usage
fi

# --- Determine authentication method ---
if [ -n "$SFTP_SECRET_ID" ]; then AUTH_METHOD="secret_manager";
elif [ -n "$SFTP_PASSWORD_FILE" ]; then AUTH_METHOD="password_file";
elif [ -n "$SFTP_PASSWORD_ENV_VAR" ]; then AUTH_METHOD="password_env";
else AUTH_METHOD="key"; fi

# --- Source all libraries AFTER parsing arguments ---
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/runtime.sh"
source "${SCRIPT_DIR}/lib/ssh_key_handler.sh"
source "${SCRIPT_DIR}/lib/workflow.sh"

# --- Handle password retrieval AFTER libraries are sourced ---
if [ "$AUTH_METHOD" = "secret_manager" ]; then
    if [ -z "$GCP_PROJECT_ID" ]; then
        # Cannot use die() yet, but this is a fatal startup error.
        echo "Error: --gcp-project-id is required when using --sftp-secret-id." >&2
        exit 1
    fi
    command -v gcloud >/dev/null 2>&1 || die "'gcloud' is not installed. It is required for Secret Manager authentication."
    log_message "INFO" "Fetching SFTP password from Google Secret Manager..."
    SFTP_PASSWORD=$(gcloud secrets versions access latest --secret="${SFTP_SECRET_ID}" --project="${GCP_PROJECT_ID}" --quiet)
    if [ -z "$SFTP_PASSWORD" ]; then die "Failed to fetch secret '${SFTP_SECRET_ID}' from project '${GCP_PROJECT_ID}'. Check ID, gcloud auth, and IAM permissions."; fi
elif [ "$AUTH_METHOD" = "password_env" ]; then
    SFTP_PASSWORD="${!SFTP_PASSWORD_ENV_VAR}"
    if [ -z "$SFTP_PASSWORD" ]; then die "--sftp-password-env was set to '${SFTP_PASSWORD_ENV_VAR}', but this environment variable is empty or not set."; fi
fi

# --- Create a unique, stable Job ID for state tracking and logging ---
JOB_ID=$(echo -n "${SFTP_USER}@${SFTP_HOST}:${SFTP_REMOTE_PATH}" | sha256sum | cut -d' ' -f1)
STATE_FILE="${STATE_DIR}/${JOB_ID}.state"

# --- Export all variables so they are available to sourced scripts ---
export SFTP_HOST SFTP_PORT SFTP_USER SFTP_PRIVATE_KEY_PATH SFTP_REMOTE_PATH
export GCS_BUCKET_NAME GCS_DESTINATION_PATH
export WORKFLOW DELETE_REMOTE_AFTER_SUCCESS DELETE_LOCAL_AFTER_SUCCESS BATCH_SIZE
export LOG_FORMAT STATE_DIR STATE_FILE JOB_ID
export AUTH_METHOD SFTP_PASSWORD_FILE SFTP_PASSWORD VERBOSE_MODE SFTP_FILE_PATTERN

# --- Helper to log the final configuration in verbose mode ---
log_configuration_summary() {
    log_debug "==================== Configuration Summary ===================="
    log_debug "SFTP Host:                ${SFTP_HOST}:${SFTP_PORT}"
    log_debug "SFTP User:                ${SFTP_USER}"
    log_debug "SFTP Remote Path:         ${SFTP_REMOTE_PATH}"
    log_debug "SFTP File Pattern:        ${SFTP_FILE_PATTERN}"
    log_debug "Authentication Method:    ${AUTH_METHOD}"
    if [ "$AUTH_METHOD" = "key" ]; then log_debug "SSH Key Path:             ${SFTP_PRIVATE_KEY_PATH}";
    elif [ "$AUTH_METHOD" = "secret_manager" ]; then
        log_debug "Secret Manager ID:        ${SFTP_SECRET_ID}"
        log_debug "GCP Project ID:           ${GCP_PROJECT_ID}"
    fi
    log_debug "Workflow:                 ${WORKFLOW}"
    log_debug "Log File Path:            ${LOG_FILE_PATH}"
    log_debug "State File Path:          ${STATE_FILE}"
    log_debug "============================================================"
}

# ==============================================================================
# MAIN EXECUTION BLOCK
# ==============================================================================
main() {
  # Create all necessary local directories
  mkdir -p "${STATE_DIR}" "${LOCAL_TEMP_DIR}" "$(dirname "${LOG_FILE_PATH}")" "$(dirname "${LOCK_FILE_PATH}")" \
    || { echo "FATAL: Could not create required .local directories."; exit 1; }

  # Set up safety features
  setup_trap
  acquire_lock

  # Start the process
  log_message "INFO" "PROCESS STARTED"
  log_configuration_summary

  # Prerequisite Checks
  command -v gsutil >/dev/null 2>&1 || die "gsutil command not found."
  command -v ssh >/dev/null 2>&1 || die "ssh command not found."

  if [ "$AUTH_METHOD" = "key" ]; then
    log_debug "Using SSH Key authentication."
    [ -f "${SFTP_PRIVATE_KEY_PATH}" ] || die "SSH private key not found at: ${SFTP_PRIVATE_KEY_PATH}."
    ensure_ssh_agent_running_and_key_added
  else
    log_debug "Using SFTP Password authentication via ${AUTH_METHOD}."
    command -v sshpass >/dev/null 2>&1 || die "'sshpass' is not installed. It is required for password authentication."
    if [ "$AUTH_METHOD" = "password_file" ]; then
      [ -f "${SFTP_PASSWORD_FILE}" ] || die "Password file not found at: ${SFTP_PASSWORD_FILE}"
    fi
  fi

  # Run the main workflow
  run_sftp_to_gcs_workflow

  log_message "INFO" "PROCESS FINISHED SUCCESSFULLY"
}

# --- Script Entrypoint ---
main "$@"