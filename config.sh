#!/bin/bash

# ==============================================================================
# SCRIPT RUNTIME DEFAULTS
# ==============================================================================
# This file defines the default operational behavior of the script.
# All paths are relative to the script's location, making it self-contained.
# ==============================================================================

# --- Self-Contained Local Paths ---
# All intermediate files are stored in a '.local' directory inside the project folder.
# This requires the SCRIPT_DIR variable to be exported by run.sh before this file is sourced.
export LOCAL_DIR="${SCRIPT_DIR}/.local"

# The directory where job state files will be stored.
export STATE_DIR="${LOCAL_DIR}/state"

# A temporary directory to stage files for the 'batch' workflow.
export LOCAL_TEMP_DIR="${LOCAL_DIR}/tmp"

# Default log file for unattended execution.
export LOG_FILE_PATH="${LOCAL_DIR}/logs/sync.log"

# Lock file to prevent concurrent runs.
export LOCK_FILE_PATH="${LOCAL_DIR}/run/sftp_to_gcs.pid"

# Location of the profiles configuration file (in the project root, not .local).
export PROFILES_FILE_PATH="${SCRIPT_DIR}/profiles.conf"

# --- Performance & Behavior Controls ---
# The number of files to process in a single batch.
export BATCH_SIZE=100

# The number of times to retry a failed command.
export RETRY_COUNT=3

# Seconds to wait between retries.
export RETRY_DELAY_SECONDS=5