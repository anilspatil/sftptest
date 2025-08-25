#!/bin/bash
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/runtime.sh"

# Lists all files in the remote directory, one per line.
sftp_list_all_files() {
    log_enter_func


    # Ensure remote path has exactly one trailing slash for clean concatenation
    local remote_path_with_slash="${SFTP_REMOTE_PATH%/}/"
    local full_remote_pattern="${remote_path_with_slash}${SFTP_FILE_PATTERN}"

    local -a cmd_array=()
    if [[ "$AUTH_METHOD" == "password_file" ]]; then cmd_array+=("sshpass" "-f" "${SFTP_PASSWORD_FILE}");
    elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then cmd_array+=("sshpass" "-p" "${SFTP_PASSWORD}"); fi

    cmd_array+=("ssh" "-p" "${SFTP_PORT}")

    if [[ "$AUTH_METHOD" != "key" ]]; then cmd_array+=("-o" "StrictHostKeyChecking=no" "-o" "PubkeyAuthentication=no");
    else cmd_array+=("-i" "${SFTP_PRIVATE_KEY_PATH}"); fi

    cmd_array+=("${SFTP_USER}@${SFTP_HOST}" "ls -1 ${full_remote_pattern}")

    log_debug "Executing list command: \"${cmd_array[@]}\""
    "${cmd_array[@]}"
    log_exit_func
}

sftp_list_all_files_new() {
    log_enter_func
    local remote_path_with_slash="${SFTP_REMOTE_PATH%/}/"
    local full_remote_pattern="${remote_path_with_slash}${SFTP_FILE_PATTERN}"

    local sftp_batch_file; sftp_batch_file=$(mktemp)
    # The 'ls' command in sftp can list remote paths with patterns directly.
    echo "ls -1 ${full_remote_pattern}" > "${sftp_batch_file}"
    log_debug "Generated SFTP batch file for listing:\n$(cat ${sftp_batch_file})"

    local -a cmd_array=()
    if [[ "$AUTH_METHOD" == "password_file" ]]; then cmd_array+=("sshpass" "-f" "${SFTP_PASSWORD_FILE}");
    elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then cmd_array+=("sshpass" "-p" "${SFTP_PASSWORD}"); fi

    # Use quiet flags to prevent "sftp>" prompts from contaminating the output
    cmd_array+=("sftp" "-q" "-o" "LogLevel=QUIET" "-P" "${SFTP_PORT}")

    if [[ "$AUTH_METHOD" != "key" ]]; then cmd_array+=("-o" "StrictHostKeyChecking=no" "-o" "PubkeyAuthentication=no");
    else cmd_array+=("-i" "${SFTP_PRIVATE_KEY_PATH}"); fi

    cmd_array+=("-b" "${sftp_batch_file}" "${SFTP_USER}@${SFTP_HOST}")

    log_debug "Executing list command: \"${cmd_array[*]}\""
    # Execute the command and capture ONLY its stdout. Errors go to stderr.
    "${cmd_array[@]}"
    local exit_code=$?
    rm -f "${sftp_batch_file}"

    # If sftp fails (e.g., path not found), it will have a non-zero exit code.
    # The main workflow will catch this because we set 'pipefail'.
    log_exit_func
    return $exit_code
}

# Downloads a specific list of files (a chunk).
sftp_download_chunk() {
    log_enter_func
    local chunk_content="$1"
    local sftp_batch_file
    sftp_batch_file=$(mktemp)

    # Build the batch file commands
    echo "cd ${SFTP_REMOTE_PATH}" > "$sftp_batch_file"
    echo "lcd ${LOCAL_TEMP_DIR}" >> "$sftp_batch_file"
    echo "$chunk_content" | grep . | sed 's/^/get "/;s/$/"/' >> "$sftp_batch_file"
    echo "quit" >> "$sftp_batch_file"
    log_debug "Generated SFTP batch file for download:\n$(cat ${sftp_batch_file})"

    local -a cmd_array=()
    if [[ "$AUTH_METHOD" == "password_file" ]]; then cmd_array+=("sshpass" "-f" "${SFTP_PASSWORD_FILE}");
    elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then cmd_array+=("sshpass" "-p" "${SFTP_PASSWORD}"); fi

    cmd_array+=("sftp" "-P" "${SFTP_PORT}") # sftp uses -P for port

    if [[ "$AUTH_METHOD" != "key" ]]; then cmd_array+=("-o" "StrictHostKeyChecking=no" "-o" "PubkeyAuthentication=no" "-o" "BatchMode=no");
    else cmd_array+=("-i" "${SFTP_PRIVATE_KEY_PATH}"); fi

    cmd_array+=("-b" "${sftp_batch_file}" "${SFTP_USER}@${SFTP_HOST}")
    log_debug "Downloading the file \"${cmd_array[*]}\""
    "${cmd_array[@]}"
    local exit_code=$?
    rm -f "${sftp_batch_file}"
    log_exit_func
    return $exit_code
}

# Deletes a specific list of files (a chunk) from the remote server.
sftp_delete_chunk() {
    log_enter_func
    local chunk_content="$1"
    local sftp_batch_file
    sftp_batch_file=$(mktemp)

    echo "cd ${SFTP_REMOTE_PATH}" > "$sftp_batch_file"
    echo "$chunk_content" | sed 's/^/rm "/;s/$/"/' >> "$sftp_batch_file"
    echo "quit" >> "$sftp_batch_file"
    log_debug "Generated SFTP batch file for deletion:\n$(cat ${sftp_batch_file})"

    local -a cmd_array=()
    if [[ "$AUTH_METHOD" == "password_file" ]]; then cmd_array+=("sshpass" "-f" "${SFTP_PASSWORD_FILE}");
    elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then cmd_array+=("sshpass" "-p" "${SFTP_PASSWORD}"); fi

    cmd_array+=("sftp" "-P" "${SFTP_PORT}") # sftp uses -P for port

    if [[ "$AUTH_METHOD" != "key" ]]; then cmd_array+=("-o" "StrictHostKeyChecking=no" "-o" "PubkeyAuthentication=no");
    else cmd_array+=("-i" "${SFTP_PRIVATE_KEY_PATH}"); fi

    cmd_array+=("-b" "${sftp_batch_file}" "${SFTP_USER}@${SFTP_HOST}")

    retry "${cmd_array[@]}"
    local exit_code=$?
    rm -f "${sftp_batch_file}"
    log_exit_func
    return $exit_code
}

# Streams a specific list of files (a chunk) one by one.
sftp_stream_chunk() {
    log_enter_func
    local chunk_content="$1"
    local failure_count=0

    echo "$chunk_content" | while read -r filename; do
        if [ -z "$filename" ]; then continue; fi

        local remote_file_path="${SFTP_REMOTE_PATH%/}/${filename}"
        local gcs_file_path="gs://${GCS_BUCKET_NAME}/${GCS_DESTINATION_PATH}${filename}"

        # For pipes, we must build a single string and execute with bash -c for retry to work
        local stream_cmd_string
        if [[ "$AUTH_METHOD" == "password_file" ]]; then
            stream_cmd_string="sshpass -f '${SFTP_PASSWORD_FILE}' ssh -p ${SFTP_PORT} -o StrictHostKeyChecking=no -o PubkeyAuthentication=no '${SFTP_USER}@${SFTP_HOST}' 'cat \"${remote_file_path}\"' | gsutil -q cp - '${gcs_file_path}'"
        elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then
            stream_cmd_string="sshpass -p '${SFTP_PASSWORD}' ssh -p ${SFTP_PORT} -o StrictHostKeyChecking=no -o PubkeyAuthentication=no '${SFTP_USER}@${SFTP_HOST}' 'cat \"${remote_file_path}\"' | gsutil -q cp - '${gcs_file_path}'"
        else
            stream_cmd_string="ssh -p ${SFTP_PORT} -i '${SFTP_PRIVATE_KEY_PATH}' '${SFTP_USER}@${SFTP_HOST}' 'cat \"${remote_file_path}\"' | gsutil -q cp - '${gcs_file_path}'"
        fi

        if ! retry bash -c "$stream_cmd_string"; then
            log_message "ERROR" "Failed to stream '${filename}' after all retries."
            ((failure_count++))
        else
            log_debug "Successfully streamed '${filename}'."
        fi
    done

    if [ $failure_count -gt 0 ]; then
        log_message "ERROR" "${failure_count} file(s) failed to stream in this chunk."
        log_exit_func
        return 1
    fi
    log_exit_func
    return 0
}