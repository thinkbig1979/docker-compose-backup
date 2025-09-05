/root/backup/backup-script/
/root/backup/backup-script/
#!/bin/bash

# rclone_backup.sh - Complete directory backup with metadata preservation

# Configuration
SOURCE_DIR="/home/backup/resticbackup"       # Change this to your source directory
REMOTE_NAME="storage-ctsvps"          # Change to your rclone remote name
BACKUP_PATH="/backup-ctsvps/resticbackup"
LOG_FILE="/var/log/rclone_backup.log"

# Validate source directory
if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory $SOURCE_DIR does not exist!" | tee -a "$LOG_FILE"
    exit 1
fi

# Backup command
echo "Starting backup of $SOURCE_DIR to $REMOTE_NAME:$BACKUP_PATH at $(date)" | tee -a "$LOG_FILE"

rclone sync --progress \
    --links \
    --transfers=4 \
    --update \
    --verbose \
    --fast-list \
    --log-file="$LOG_FILE" \
    "$SOURCE_DIR" \
    "$REMOTE_NAME:$BACKUP_PATH"

# Check exit status
if [ $? -eq 0 ]; then
    echo "Backup completed successfully at $(date)" | tee -a "$LOG_FILE"
else
    echo "Backup FAILED! Check $LOG_FILE for details" | tee -a "$LOG_FILE"
    exit 1
fi
