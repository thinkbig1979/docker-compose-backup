# Usage Guide

## Getting Started

### 1. Installation
```bash
git clone <repository>
cd backup-script
./install.sh
```

### 2. Configuration
```bash
# Edit main configuration
nano config/backup.conf

# Configure cloud storage (optional)
rclone config
```

### 3. First Run
```bash
# Launch TUI for guided setup
./bin/backup-tui.sh

# Or run backup directly
./bin/docker-backup.sh --dry-run
```

## Main Interface (TUI)

The Text User Interface provides unified access to all backup functions:

```bash
./bin/backup-tui.sh
```

### Main Menu Options

1. **Stage 1: Docker Backup** - Local restic backups
2. **Stage 2: Cloud Sync** - Upload to cloud storage  
3. **Stage 3: Cloud Restore** - Download from cloud
4. **Directory Management** - Select which stacks to backup
5. **System Status** - View logs and system health
6. **Configuration** - Edit settings and validate setup

### Quick Actions
- **F1**: Help
- **F2**: Directory Management
- **F3**: System Status  
- **F4**: Settings
- **ESC**: Exit

## Command Line Usage

### Stage 1: Docker Backup

```bash
# Full backup with TUI progress
./bin/docker-backup.sh

# Dry run to test configuration
./bin/docker-backup.sh --dry-run

# Quiet mode (minimal output)
./bin/docker-backup.sh --quiet

# Help and options
./bin/docker-backup.sh --help
```

### Stage 2: Cloud Sync

```bash
# Sync to default remote
./scripts/rclone_backup.sh

# Sync to specific remote
./scripts/rclone_backup.sh /path/to/restic/repo remote:backup-path

# Dry run
./scripts/rclone_backup.sh --dry-run
```

### Stage 3: Cloud Restore

```bash
# Restore from default remote  
./scripts/rclone_restore.sh

# Restore from specific remote
./scripts/rclone_restore.sh remote:backup-path /local/restore/path

# Dry run
./scripts/rclone_restore.sh --dry-run
```

### Directory Management

```bash
# Interactive TUI for directory selection
./bin/manage-dirlist.sh

# Command line options
./bin/manage-dirlist.sh --help
```

## Workflow Examples

### Daily Backup Routine

```bash
# Option 1: All stages via TUI
./bin/backup-tui.sh

# Option 2: Individual stages
./bin/docker-backup.sh           # Stage 1: Local backup
./scripts/rclone_backup.sh       # Stage 2: Cloud sync
```

### Weekly Maintenance

```bash
# 1. Verify backup integrity
./bin/backup-tui.sh → System Status → Verify Backups

# 2. Clean old snapshots
restic forget --repo /path/to/repo --keep-daily 7 --keep-weekly 4

# 3. Check cloud storage
rclone check /path/to/repo remote:backup-path
```

### Disaster Recovery

```bash
# 1. Restore repository from cloud
./scripts/rclone_restore.sh remote:backup-path /new/repo/path

# 2. Browse available snapshots
restic snapshots --repo /new/repo/path

# 3. Restore specific data
restic restore latest --repo /new/repo/path --target /restore/location
```

## Directory Selection

### Using the TUI
1. Launch: `./bin/manage-dirlist.sh`
2. Use space to toggle directory selection
3. Select **Save** to apply changes

### Manual Editing
```bash
# Edit dirlist file directly
nano dirlist

# Example content:
webapp        # Enable webapp backup
database      # Enable database backup  
# monitoring  # Disable monitoring backup
```

### Automatic Discovery
The system automatically discovers Docker compose directories in your `BACKUP_DIR` and allows you to enable/disable each one.

## Monitoring and Logging

### Log Files
```bash
# View backup logs
tail -f logs/docker_backup.log

# View TUI logs  
tail -f logs/backup_tui.log

# View all logs
./bin/backup-tui.sh → System Status → View Logs
```

### Status Checking
```bash
# System health check
./bin/backup-tui.sh → System Status

# Verify last backup
restic snapshots --repo /path/to/repo | tail -5

# Check cloud sync status
rclone lsl remote:backup-path
```

## Automation

### Cron Jobs

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup-script/bin/docker-backup.sh >> /var/log/backup.log 2>&1

# Weekly cloud sync on Sundays at 3 AM  
0 3 * * 0 /path/to/backup-script/scripts/rclone_backup.sh >> /var/log/backup.log 2>&1
```

### Systemd Service

```ini
# /etc/systemd/system/docker-backup.service
[Unit]
Description=Docker Stack Backup
After=docker.service

[Service]
Type=oneshot
User=backup
ExecStart=/path/to/backup-script/bin/docker-backup.sh
```

```ini
# /etc/systemd/system/docker-backup.timer
[Unit]
Description=Daily Docker Backup
Requires=docker-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

## Troubleshooting

### Common Commands

```bash
# Test configuration
./bin/docker-backup.sh --dry-run

# Check restic repository
restic check --repo /path/to/repo

# Verify rclone connectivity
rclone lsd remote:

# View detailed logs
export LOG_LEVEL="DEBUG"
./bin/docker-backup.sh --dry-run
```

### Recovery Scenarios

**Corrupted local repository**:
```bash
./scripts/rclone_restore.sh remote:backup-path /new/repo/path
```

**Lost configuration**:
```bash
cp config/backup.conf.template config/backup.conf
# Edit with your settings
```

**Missing directories**:
```bash
./bin/manage-dirlist.sh --prune  # Sync with filesystem
```

## Performance Tips

1. **Use SSD storage** for restic repository
2. **Exclude unnecessary data** via restic excludes  
3. **Monitor system resources** during backup
4. **Schedule backups** during low-usage periods
5. **Use incremental backups** (restic default behavior)

## Security Best Practices

1. **Encrypt restic repository** with strong password
2. **Secure configuration files** (chmod 600)
3. **Use rclone encryption** for sensitive cloud data  
4. **Rotate backup passwords** regularly
5. **Monitor access logs** for unauthorized access