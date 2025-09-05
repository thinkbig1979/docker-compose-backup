/root/backup/backup-script/
/root/backup/backup-script/
#!/bin/bash

# rclone_restore.sh - Complete directory restore with metadata preservation

# Configuration
REMOTE_NAME="your_remote"          # Change to your rclone remote name
BACKUP_PATH="backup/latest"       # Change to your backup path or use a specific timestamp
RESTORE_DIR="/path/to/restore"    # Change to your restore location
LOG_FILE="/var/log/rclone_restore.log"

# Validate restore location
if [ ! -d "$RESTORE_DIR" ]; then
    echo "Creating restore directory $RESTORE_DIR" | tee -a "$LOG_FILE"
    mkdir -p "$RESTORE_DIR" || {
        echo "Failed to create restore directory!" | tee -a "$LOG_FILE"
        exit 1
    }
fi

# Restore command
echo "Starting restore from $REMOTE_NAME:$BACKUP_PATH to $RESTORE_DIR at $(date)" | tee -a "$LOG_FILE"

rclone copy --progress \
    --links \
    --transfers=4 \
    --verbose \
    --fast-list \
    --log-file="$LOG_FILE" \
    "$REMOTE_NAME:$BACKUP_PATH" \
    "$RESTORE_DIR"


# Check exit status
if [ $? -eq 0 ]; then
    echo "Restore completed successfully at $(date)" | tee -a "$LOG_FILE"
else
    echo "Restore FAILED! Check $LOG_FILE for details" | tee -a "$LOG_FILE"
    exit 1
fi
