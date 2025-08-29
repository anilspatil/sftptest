#!/bin/bash
source "${SCRIPT_DIR}/lib/common.sh"; source "${SCRIPT_DIR}/lib/runtime.sh"

# This is the single, unified function for executing SFTP commands via a batch file.
# It works by piping the batch file into a remote sftp process via ssh.
# This is the most compatible method for all SFTP servers, including jailed ones.
_execute_sftp_batch_commands() {
    local sftp_commands="$1"

    # This array builds the ssh command that will execute the sftp client remotely.
    local -a cmd_array=()
    if [[ "$AUTH_METHOD" == "password_file" ]]; then cmd_array+=("sshpass" "-f" "${SFTP_PASSWORD_FILE}");
    elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then cmd_array+=("sshpass" "-p" "${SFTP_PASSWORD}"); fi

    cmd_array+=("ssh" "-p" "${SFTP_PORT}")

    if [[ "$AUTH_METHOD" != "key" ]]; then cmd_array+=("-o" "StrictHostKeyChecking=no" "-o" "PubkeyAuthentication=no");
    else cmd_array+=("-i" "${SFTP_PRIVATE_KEY_PATH}"); fi

    # The remote command is "sftp", which tells the server to start an sftp session.
    # We will pipe our commands into this session's stdin.
    cmd_array+=("${SFTP_USER}@${SFTP_HOST}" "sftp")

    log_debug "Executing SFTP batch via SSH pipe: \"${cmd_array[@]}\""

    # We redirect our commands into the stdin of the ssh command.
    local output
    local exit_code
    output=$(echo -e "${sftp_commands}" | "${cmd_array[@]}" 2>&1)
    exit_code=$?

    log_debug "SFTP command output:\n${output}"
    # A successful sftp session exits with 0.
    if [[ $exit_code -ne 0 ]]; then
        log_message "WARN" "SFTP command block failed with exit code ${exit_code}."
        return $exit_code
    fi
    return 0
}

# This function uses the simple, proven ssh 'ls' command to get the file list.
# It now uses the robust "cd && ls" pattern.
sftp_list_all_files() {
    log_enter_func

    # Construct the remote command to first change directory, then list files.
    # This is more robust for servers that don't handle path expansion well.
    local remote_command="cd '${SFTP_REMOTE_PATH}' && ls -1 ${SFTP_FILE_PATTERN}"

    local -a cmd_array=()
    if [[ "$AUTH_METHOD" == "password_file" ]]; then cmd_array+=("sshpass" "-f" "${SFTP_PASSWORD_FILE}");
    elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then cmd_array+=("sshpass" "-p" "${SFTP_PASSWORD}"); fi

    cmd_array+=("ssh" "-p" "${SFTP_PORT}")

    if [[ "$AUTH_METHOD" != "key" ]]; then cmd_array+=("-o" "StrictHostKeyChecking=no" "-o" "PubkeyAuthentication=no");
    else cmd_array+=("-i" "${SFTP_PRIVATE_KEY_PATH}"); fi

    cmd_array+=("${SFTP_USER}@${SFTP_HOST}" "${remote_command}")

    log_debug "Executing list command: \"${cmd_array[@]}\""
    "${cmd_array[@]}"
    log_exit_func
}

# This function now uses the new, robust helper to download files.
sftp_download_chunk() {
    log_enter_func; local chunk_content="$1"

    # Build the full multi-line command string for the batch file.
    local download_commands="cd '${SFTP_REMOTE_PATH}'\nlcd '${LOCAL_TEMP_DIR}'\n"
    download_commands+=$(echo "$chunk_content" | grep . | sed 's/^/get "/;s/$/"/')

    retry _execute_sftp_batch_commands "${download_commands}"
    local exit_code=$?; log_exit_func; return $exit_code
}

# This function now uses the new, robust helper to delete files.
sftp_delete_chunk() {
    log_enter_func; local chunk_content="$1"

    local delete_commands="cd '${SFTP_REMOTE_PATH}'\n"
    delete_commands+=$(echo "$chunk_content" | grep . | sed 's/^/rm "/;s/$/"/')

    retry _execute_sftp_batch_commands "${delete_commands}"
    local exit_code=$?; log_exit_func; return $exit_code
}

# This function already uses the correct ssh 'cat' command for streaming.
sftp_stream_chunk() {
    log_enter_func; local chunk_content="$1"; local failure_count=0
    echo "$chunk_content" | while read -r filename; do
        if [ -z "$filename" ]; then continue; fi
        local remote_file_path="${SFTP_REMOTE_PATH%/}/${filename}"; local gcs_file_path="gs://${GCS_BUCKET_NAME}/${GCS_DESTINATION_PATH}${filename}"
        local stream_cmd_string
        if [[ "$AUTH_METHOD" == "password_file" ]]; then stream_cmd_string="sshpass -f '${SFTP_PASSWORD_FILE}' ssh -p ${SFTP_PORT} -o StrictHostKeyChecking=no -o PubkeyAuthentication=no '${SFTP_USER}@${SFTP_HOST}' 'cat \"${remote_file_path}\"' | gsutil -q cp - '${gcs_file_path}'";
        elif [[ "$AUTH_METHOD" == "password_env" || "$AUTH_METHOD" == "secret_manager" ]]; then stream_cmd_string="sshpass -p '${SFTP_PASSWORD}' ssh -p ${SFTP_PORT} -o StrictHostKeyChecking=no -o PubkeyAuthentication=no '${SFTP_USER}@${SFTP_HOST}' 'cat \"${remote_file_path}\"' | gsutil -q cp - '${gcs_file_path}'";
        else stream_cmd_string="ssh -p ${SFTP_PORT} -i '${SFTP_PRIVATE_KEY_PATH}' '${SFTP_USER}@${SFTP_HOST}' 'cat \"${remote_file_path}\"' | gsutil -q cp - '${gcs_file_path}'"; fi
        if ! retry bash -c "$stream_cmd_string"; then
            log_message "ERROR" "Failed to stream '${filename}' after all retries."; ((failure_count++))
        else log_debug "Successfully streamed '${filename}'."; fi
    done
    if [ $failure_count -gt 0 ]; then
        log_message "ERROR" "${failure_count} file(s) failed to stream in this chunk."
        log_exit_func; return 1
    fi; log_exit_func; return 0
}