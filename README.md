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
## Usage
Run `./run.sh --help` for a full list of all available options.
### Example 1: Using the Reliable Password File Method (Recommended for Testing)
```bash
# First, create and secure the password file:
echo "password" > .sftp_pass && chmod 600 .sftp_pass

# Then, run the script to download only .png files:
./run.sh \
  --sftp-host test.rebex.net \
  --sftp-user demo \
  --sftp-remote-path /pub/example/ \
  --gcs-bucket your-fake-bucket \
  --sftp-password-file .sftp_pass \
  --file-pattern "*.png" \
  --verbose