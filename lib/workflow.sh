#!/bin/bash
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/runtime.sh"
source "${SCRIPT_DIR}/lib/sftp_handler.sh"
source "${SCRIPT_DIR}/lib/gcs_handler.sh"

# This is the main, unified workflow that handles batching, state, and both transfer methods.
run_sftp_to_gcs_workflow() {
  log_enter_func
  local start_time
  start_time=$(date +%s)

  # 1. Get file lists and determine what needs to be processed
  log_message "INFO" "Fetching remote file list using pattern '${SFTP_FILE_PATTERN}'..."
  local remote_files
  remote_files=$(sftp_list_all_files)
  if [ $? -ne 0 ]; then die "Could not list remote files."; fi
  log_debug "Raw remote file list:\n${remote_files}"

  log_message "INFO" "Reading state file to find previously processed files..."
  local processed_files
  processed_files=$(read_state_file)
  log_debug "Previously processed files:\n${processed_files}"

  local files_to_process
  if [ -z "$processed_files" ]; then
    files_to_process="$remote_files"
  else
    # Use grep to find lines in remote_files that are NOT in processed_files
    files_to_process=$(echo "$remote_files" | grep -vFf <(echo "$processed_files"))
  fi

  if [ -z "$files_to_process" ]; then
    log_message "INFO" "No new files to process. All files are up-to-date."
    log_exit_func
    return 0
  fi

  local total_files_count
  total_files_count=$(echo "$files_to_process" | wc -l | xargs)
  log_message "INFO" "Found ${total_files_count} new files to process."
  log_debug "Files to be processed in this run:\n${files_to_process}"

  # 2. Process the file list in manually constructed chunks.
  local chunk_num=1
  local line_count=0
  local current_chunk=""

  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi

    current_chunk+="${line}"$'\n'
    ((line_count++))

    if (( line_count % BATCH_SIZE == 0 )) || (( line_count == total_files_count )); then
      local chunk_file_count
      chunk_file_count=$(echo -n "$current_chunk" | wc -l | xargs)
      log_message "INFO" "Processing chunk #${chunk_num} with ${chunk_file_count} file(s)..."
      log_debug "Files in chunk #${chunk_num}:\n${current_chunk}"

      local chunk_start_time
      chunk_start_time=$(date +%s)
      local chunk_succeeded=false

      if [ "$WORKFLOW" = "batch" ]; then
        if sftp_download_chunk "$current_chunk" && gcs_upload_files && gcs_cleanup_local; then
          chunk_succeeded=true
        fi
      elif [ "$WORKFLOW" = "streaming" ]; then
        if sftp_stream_chunk "$current_chunk"; then
          chunk_succeeded=true
        fi
      fi

      # 3. If chunk was successful, update state and clean up remote
      if $chunk_succeeded; then
        local chunk_end_time
        chunk_end_time=$(date +%s)
        local duration=$((chunk_end_time - chunk_start_time))
        log_message "SUCCESS" "Chunk #${chunk_num} processed successfully in ${duration} seconds."
        echo -n "$current_chunk" | update_state_file

        if [ "${DELETE_REMOTE_AFTER_SUCCESS}" = true ]; then
          sftp_delete_chunk "$current_chunk" || log_message "WARN" "Failed to delete remote files for chunk #${chunk_num}."
        fi
      else
        die "Processing failed on chunk #${chunk_num}. The job will halt. State has not been updated for this chunk."
      fi

      # Reset for the next chunk
      ((chunk_num++))
      current_chunk=""
    fi
  done <<< "$files_to_process"

  local end_time
  end_time=$(date +%s)
  local total_duration=$((end_time - start_time))
  log_debug "Entire workflow completed in ${total_duration} seconds."
  log_exit_func
}