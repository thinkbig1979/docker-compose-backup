# Usage Guide

## Getting Started

### 1. Installation
```bash
git clone <repository>
cd backup-script
go build -o bin/backup-tui ./cmd/backup-tui
```

### 2. Configuration
```bash
# Edit main configuration
nano config/config.ini

# Configure cloud storage (optional)
rclone config
```

### 3. First Run
```bash
# Launch TUI for guided setup
./bin/backup-tui

# Or run backup directly
./bin/backup-tui backup --dry-run
```

## Main Interface (TUI)

The Text User Interface provides unified access to all backup functions:

```bash
./bin/backup-tui
```

### Main Menu Options

1. **Backup (Stage 1: Local)** - Run local backup with restic
2. **Cloud Sync (Stage 2: Upload)** - Sync to cloud storage
3. **Cloud Restore (Stage 3: Download)** - Restore from cloud
4. **Directory Management** - Select which stacks to backup
5. **Status & Logs** - View system status
6. **Restic Repository** - Manage snapshots and repository

### Quick Actions
- **R**: Run backup now
- **↑/↓**: Navigate menu
- **Enter**: Select option
- **Q**: Quit

## Command Line Usage

### Stage 1: Docker Backup

```bash
# Full backup with progress output
./bin/backup-tui backup

# Dry run to test configuration
./bin/backup-tui backup --dry-run

# With custom config file
./bin/backup-tui backup --config /path/to/config.ini

# Help and options
./bin/backup-tui backup --help
```

### Stage 2: Cloud Sync

```bash
# Sync to configured remote
./bin/backup-tui sync

# Dry run
./bin/backup-tui sync --dry-run
```

### Stage 3: Cloud Restore

```bash
# Restore from configured remote
./bin/backup-tui restore

# Restore to specific path
./bin/backup-tui restore --target /local/restore/path

# Dry run
./bin/backup-tui restore --dry-run
```

### Other Commands

```bash
# Validate configuration
./bin/backup-tui validate

# Show status
./bin/backup-tui status
```

## Workflow Examples

### Daily Backup Routine

```bash
# Option 1: Interactive TUI
./bin/backup-tui

# Option 2: Headless backup
./bin/backup-tui backup           # Stage 1: Local backup
./bin/backup-tui sync             # Stage 2: Cloud sync
```

### Weekly Maintenance

```bash
# 1. Verify backup integrity (via TUI)
./bin/backup-tui
# Navigate to: Restic Repository → Check Repository

# 2. Clean old snapshots (via TUI)
# Navigate to: Restic Repository → Prune Repository

# 3. Or use restic directly
restic forget --repo /path/to/repo --keep-daily 7 --keep-weekly 4 --prune
```

### Disaster Recovery

```bash
# 1. Restore repository from cloud
./bin/backup-tui restore --target /new/repo/path

# 2. Browse available snapshots
restic snapshots --repo /new/repo/path

# 3. Restore specific data
restic restore latest --repo /new/repo/path --target /restore/location
```

## Directory Selection

### Using the TUI
1. Launch: `./bin/backup-tui`
2. Select **Directory Management**
3. Use **Space** or **Enter** to toggle directory selection
4. Press **A** to enable all, **N** to disable all
5. Press **S** to save changes

### Manual Editing
```bash
# Edit dirlist file directly
nano dirlist

# Example content:
+webapp        # Enable webapp backup
+database      # Enable database backup
-monitoring   # Disable monitoring backup
```

### External Paths
You can add external paths (outside DOCKER_STACKS_DIR) via the TUI:
1. Open Directory Management
2. Press **X** to add external path
3. Enter the full path to the directory
4. Toggle enabled/disabled as needed

### Automatic Discovery
The system automatically discovers Docker compose directories in your `DOCKER_STACKS_DIR` and allows you to enable/disable each one. New directories are disabled by default.

## Monitoring and Logging

### Log Output
The TUI displays real-time progress during backup operations. For headless mode:

```bash
# Run with output to log file
./bin/backup-tui backup 2>&1 | tee backup.log

# View logs via TUI
./bin/backup-tui
# Navigate to: Status & Logs
```

### Status Checking
```bash
# Quick status check
./bin/backup-tui status

# Via TUI
./bin/backup-tui
# Navigate to: Status & Logs

# Verify last backup with restic
restic snapshots --repo /path/to/repo | tail -5
```

## Automation

### Cron Jobs

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup-script/bin/backup-tui backup >> /var/log/backup.log 2>&1

# Weekly cloud sync on Sundays at 3 AM
0 3 * * 0 /path/to/backup-script/bin/backup-tui sync >> /var/log/backup.log 2>&1
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
ExecStart=/path/to/backup-script/bin/backup-tui backup
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
./bin/backup-tui backup --dry-run

# Validate config file
./bin/backup-tui validate

# Check restic repository
restic check --repo /path/to/repo

# Verify rclone connectivity
rclone lsd remote:
```

### Container Management Issues

If containers fail to stop or start:

```bash
# Check container status manually
docker compose -f /path/to/stack/docker-compose.yml ps

# Force stop containers
docker compose -f /path/to/stack/docker-compose.yml down --timeout 10

# Restart containers manually
docker compose -f /path/to/stack/docker-compose.yml up -d
```

The backup system uses `docker compose down/up -d` (not stop/start) for more reliable container management. If a timeout occurs, the entire process group is killed to prevent hung processes.

### Recovery Scenarios

**Corrupted local repository**:
```bash
./bin/backup-tui restore --target /new/repo/path
```

**Lost configuration**:
```bash
cp config/config.ini.template config/config.ini
# Edit with your settings
```

**Missing directories**:
```bash
# The system auto-discovers directories on startup
# Use the TUI to enable/disable as needed
./bin/backup-tui
# Navigate to: Directory Management
```

## Performance Tips

1. **Use SSD storage** for restic repository
2. **Configure appropriate timeouts** in config.ini
3. **Schedule backups** during low-usage periods
4. **Use incremental backups** (restic default behavior)
5. **Monitor DOCKER_TIMEOUT** - increase if containers are slow to stop

## Security Best Practices

1. **Encrypt restic repository** with strong password
2. **Secure configuration files** (chmod 600 config/config.ini)
3. **Use rclone encryption** for sensitive cloud data
4. **Rotate backup passwords** regularly
5. **Use password file** instead of plaintext in config
