# Generic SFTP to GCS Sync Utility (Enterprise Edition)
This is the definitive, debugged version of the script. It provides a modular, robust, and enterprise-grade utility to transfer files from an SFTP server to a Google Cloud Storage (GCS) bucket.
## Key Features
- **File Pattern Matching**: Use the `--file-pattern` flag to transfer only specific files (e.g., `*.csv`).
- **Secure Authentication**: Natively supports **Google Secret Manager**, SSH keys (default), and legacy password files.
- **Self-Contained & Portable**: Requires **no root permissions**. All working files are created within a `.local` directory inside the project folder.
- **Robust Command Execution**: Uses standard, safe bash practices to build and execute commands, preventing errors from special characters in paths or passwords.
- **Idempotent & Resumable**: A state file tracks successfully transferred files, allowing jobs to resume safely.
- **Verbose Debug Mode**: Use the `--verbose` flag to get detailed logs for easy troubleshooting.
## Prerequisites
1.  **`gcloud` CLI**: Required for GCS operations and Secret Manager.
2.  **`ssh` Client**: Standard on most Linux/macOS systems.
3.  **`sshpass` (Optional)**: Required **only** if you use any form of password-based authentication.  
- **Automatic Installation:** If `sshpass` is not found, the script will automatically attempt to install it using `sudo` and your system's package manager (`apt-get`, `dnf`, `yum`).
- **Sudo Requirement:** This automatic installation requires that the user running the script has `sudo` privileges. In a fully unattended environment (like a cron job), you should either pre-install `sshpass` or configure passwordless `sudo` to avoid the script hanging on a password prompt.

## Authentication Methods

The script evaluates authentication methods in the following order of priority:

### 1. Google Secret Manager (Recommended for Passwords)

This is the most secure method for handling passwords.
- **Flag**: `--sftp-secret-id YOUR_SECRET_NAME`
- **Flag**: `--gcp-project-id YOUR_PROJECT_ID` **(Required with secret ID)**
- **Setup**:
    1.  Enable the Secret Manager API in your Google Cloud project.
    2.  Create a secret containing your SFTP password.
    3.  Grant the **`Secret Manager Secret Accessor`** IAM role to the user or service account running the script.

### 2. SSH Key / Passphrase (Default Method)

## Usage

### Example 1: Using Google Secret Manager (Most Secure)
```bash
./run.sh \
  --sftp-host sftp.example.com \
  --sftp-user sftpuser \
  --sftp-remote-path /exports/ \
  --gcs-bucket my-gcs-bucket \
  --sftp-secret-id "sftp-prod-password" \
  --gcp-project-id "my-gcp-project-123"