#!/bin/bash
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/runtime.sh"

gcs_upload_files() {
  log_enter_func

  if [ -z "$(ls -A ${LOCAL_TEMP_DIR} 2>/dev/null)" ]; then
    log_message "INFO" "No files found in temp directory. Nothing to upload."
    log_exit_func
    return 0
  fi

  local gcs_uri="gs://${GCS_BUCKET_NAME}/${GCS_DESTINATION_PATH}"
  log_debug "Uploading contents of ${LOCAL_TEMP_DIR} to ${gcs_uri}"

  retry gsutil -m cp "${LOCAL_TEMP_DIR}/*" "${gcs_uri}"
  local exit_code=$?
  log_exit_func
  return $exit_code
}

gcs_cleanup_local() {
  log_enter_func
  if [ ! -d "${LOCAL_TEMP_DIR}" ]; then
    log_exit_func
    return
  fi
  log_debug "Cleaning up local temporary directory: ${LOCAL_TEMP_DIR}"
  rm -rf "${LOCAL_TEMP_DIR}"/*
  log_exit_func
}