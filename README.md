# Docker Stack 3-Stage Backup System

A comprehensive 3-stage backup solution for Docker compose stacks using restic with cloud synchronization.

## Quick Start

```bash
# 1. Run installation
./install.sh

# 2. Configure (edit config/backup.conf)
cp config/backup.conf.template config/backup.conf
nano config/backup.conf

# 3. Select directories for backup
./bin/backup-tui-go              # Launch TUI

# 4. Run backup (dry-run first)
./bin/backup-tui-go backup --dry-run -v

# 5. Run actual backup
./bin/backup-tui-go backup -v

# 6. (Optional) Cloud sync
./bin/backup-tui-go sync         # Upload to cloud
./bin/backup-tui-go restore      # Restore from cloud
```

## 3-Stage Architecture

**Stage 1: Local Restic Backup** → **Stage 2: Cloud Sync** → **Stage 3: Disaster Recovery**

All three stages are managed by a single unified binary: `backup-tui-go`

## Unified TUI Binary

The `backup-tui-go` binary provides both an interactive TUI and headless CLI commands:

```bash
# Interactive TUI mode (default)
./bin/backup-tui-go

# Headless CLI commands
./bin/backup-tui-go backup              # Stage 1: Local backup
./bin/backup-tui-go backup --dry-run    # Preview backup
./bin/backup-tui-go sync                # Stage 2: Cloud sync
./bin/backup-tui-go sync --dry-run      # Preview sync
./bin/backup-tui-go restore [PATH]      # Stage 3: Restore from cloud
./bin/backup-tui-go status              # Show system status
./bin/backup-tui-go validate            # Validate configuration
./bin/backup-tui-go list-backups        # List backup snapshots
./bin/backup-tui-go health              # Run health diagnostics

# Common flags
-v, --verbose     Enable verbose output
-n, --dry-run     Perform dry run (no changes)
-c, --config      Path to config file
-h, --help        Show help message
```

## Repository Structure

```
├── bin/                       # Executables
│   └── backup-tui-go          # Unified backup tool (Go binary)
├── cmd/
│   └── backup-tui/            # Main entry point source
├── internal/                  # Go packages
│   ├── config/                # INI config parser
│   ├── backup/                # Docker + restic operations
│   ├── cloud/                 # rclone sync/restore
│   ├── dirlist/               # Directory management
│   ├── tui/                   # TUI screens
│   └── util/                  # Utilities (exec, lock, log)
├── config/                    # Configuration files
│   ├── backup.conf            # Main configuration
│   └── backup.conf.template   # Template with comments
├── locks/                     # Lock files
├── logs/                      # Runtime logs
├── dirlist                    # Directory enable/disable list
└── go.mod                     # Go module
```

## Configuration

The configuration uses INI-style sections:

```ini
# config/backup.conf

[docker]
DOCKER_STACKS_DIR=/opt/docker-stacks
DOCKER_TIMEOUT=300

[local_backup]
RESTIC_REPOSITORY=/mnt/backup/restic-repo
RESTIC_PASSWORD=your-password
KEEP_DAILY=7
KEEP_WEEKLY=4
AUTO_PRUNE=true

[cloud_sync]
RCLONE_REMOTE=backblaze
RCLONE_PATH=/backup/restic
TRANSFERS=4
```

**Legacy flat format is also supported for backwards compatibility.**

### Configuration Steps

1. Copy the template:
   ```bash
   cp config/backup.conf.template config/backup.conf
   chmod 600 config/backup.conf
   ```

2. Edit with your settings:
   ```bash
   nano config/backup.conf
   ```

3. Configure rclone for cloud storage (optional):
   ```bash
   rclone config
   ```

4. Validate configuration:
   ```bash
   ./bin/backup-tui-go validate
   ```

## Features

- **Unified Binary** - Single tool for all backup operations
- **Interactive TUI** - Menu-driven interface with tview
- **Headless CLI** - Full scripting/cron support
- **Selective Backup** - Choose which Docker stacks to backup
- **Smart Docker Management** - Only stops/starts running containers
- **Retry Logic** - Automatic retries for cloud operations
- **File Locking** - Prevents concurrent operations
- **Signal Handling** - Graceful shutdown with cleanup
- **Dry Run Mode** - Preview operations before execution
- **Comprehensive Logging** - Detailed logs to file and console

## Prerequisites

```bash
# Required
sudo apt-get install restic docker.io docker-compose-v2

# Optional (for cloud sync - Stage 2 & 3)
sudo apt-get install rclone

# Build from source (optional)
go build -o bin/backup-tui-go ./cmd/backup-tui/
```

## TUI Menu Structure

```
MAIN MENU
├── 1. Backup (Stage 1: Local)
│   ├── Quick Backup
│   ├── Dry Run
│   └── List Snapshots
├── 2. Cloud Sync (Stage 2: Upload)
│   ├── Quick Sync
│   ├── Dry Run
│   └── Test Connectivity
├── 3. Cloud Restore (Stage 3: Download)
│   ├── Restore Repository
│   └── Test Connectivity
├── 4. Directory Management
│   └── Select/Toggle Directories
├── 5. Status & Logs
├── Q. Quick Backup (shortcut)
├── S. Quick Status (shortcut)
└── 0. Exit
```

## Cron Example

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup-tui-go backup -v >> /var/log/backup.log 2>&1

# Weekly cloud sync on Sundays at 3 AM
0 3 * * 0 /path/to/backup-tui-go sync -v >> /var/log/backup-sync.log 2>&1
```

---

**Self-Contained Design**: All configuration and data files are kept within this directory for complete portability.
