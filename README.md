# Docker Stack 3-Stage Backup System

[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blue)](https://claude.ai)

A comprehensive 3-stage backup solution for Docker compose stacks using restic for local backups and rclone for cloud synchronization. The tool uses `docker compose down/up -d` for robust container management, ensuring data consistency during backups. Only containers that were running before backup are restarted afterward. Supports backing up stacks from your main Docker directory as well as external paths anywhere on your filesystem.

## Quick Start

```bash
# 1. Build the binary
go build -o bin/backup-tui ./cmd/backup-tui

# 2. Configure (edit config/config.ini)
cp config/config.ini.template config/config.ini
nano config/config.ini

# 3. Select directories for backup
./bin/backup-tui              # Launch TUI

# 4. Run backup (dry-run first)
./bin/backup-tui backup --dry-run -v

# 5. Run actual backup
./bin/backup-tui backup -v

# 6. (Optional) Cloud sync
./bin/backup-tui sync         # Upload to cloud
./bin/backup-tui restore      # Restore from cloud
```

## 3-Stage Architecture

**Stage 1: Local Restic Backup** → **Stage 2: Cloud Sync** → **Stage 3: Disaster Recovery**

All three stages are managed by a single unified binary: `backup-tui`

### Data Flow

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│   Docker Stacks     │     │   Restic Repository │     │    Cloud Storage    │
│  (DOCKER_STACKS_DIR)│     │  (RESTIC_REPOSITORY)│     │ (RCLONE_REMOTE:PATH)│
└──────────┬──────────┘     └──────────┬──────────┘     └──────────┬──────────┘
           │                           │                           │
           │  Stage 1: backup          │  Stage 2: sync            │
           │  (restic backup)          │  (rclone sync)            │
           ├──────────────────────────►├──────────────────────────►│
           │                           │                           │
           │                           │  Stage 3: restore         │
           │                           │◄──────────────────────────┤
           │                           │  (rclone sync)            │
           │                           │                           │
└──────────────────────────────────────┴───────────────────────────┘
```

- **Stage 1**: Uses `docker compose down` to stop containers, backs up stack directories to local restic repository, uses `docker compose up -d` to restart containers
- **Stage 2**: Syncs the entire restic repository to cloud storage (preserves deduplication and snapshots)
- **Stage 3**: Restores the restic repository from cloud to a local path for disaster recovery

## Unified TUI Binary

The `backup-tui` binary provides both an interactive TUI and headless CLI commands:

```bash
# Interactive TUI mode (default)
./bin/backup-tui

# Headless CLI commands
./bin/backup-tui backup              # Stage 1: Local backup
./bin/backup-tui backup --dry-run    # Preview backup
./bin/backup-tui sync                # Stage 2: Cloud sync
./bin/backup-tui sync --dry-run      # Preview sync
./bin/backup-tui restore [PATH]      # Stage 3: Restore from cloud
./bin/backup-tui status              # Show system status
./bin/backup-tui validate            # Validate configuration
./bin/backup-tui list-backups        # List backup snapshots
./bin/backup-tui health              # Run health diagnostics

# Common flags
-v, --verbose     Enable verbose output
-n, --dry-run     Perform dry run (no changes)
-c, --config      Path to config file
-h, --help        Show help message
```

## Repository Structure

```
├── bin/                       # Executables
│   └── backup-tui          # Unified backup tool (Go binary)
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
│   ├── config.ini            # Main configuration
│   └── config.ini.template   # Template with comments
├── locks/                     # Lock files
├── logs/                      # Runtime logs
├── dirlist                    # Directory enable/disable list
└── go.mod                     # Go module
```

## Configuration

The configuration uses INI-style sections:

```ini
# config/config.ini

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

### Configuration Steps

1. Copy the template:
   ```bash
   cp config/config.ini.template config/config.ini
   chmod 600 config/config.ini
   ```

2. Edit with your settings:
   ```bash
   nano config/config.ini
   ```

3. Configure rclone for cloud storage (optional):
   ```bash
   rclone config
   ```

4. Validate configuration:
   ```bash
   ./bin/backup-tui validate
   ```

## Features

- **Unified Binary** - Single tool for all backup operations
- **Interactive TUI** - Menu-driven interface with Bubbletea
- **Headless CLI** - Full scripting/cron support
- **Selective Backup** - Choose which Docker stacks to backup
- **External Paths** - Add Docker stacks from anywhere on your filesystem
- **Robust Container Management** - Uses `docker compose down/up -d` for clean container lifecycle
- **Smart State Tracking** - Only restarts containers that were running before backup
- **Defensive StateUnknown Handling** - Restarts containers when state is uncertain
- **Process Group Timeout** - Kills entire process tree on timeout (no hung processes)
- **Verification with Retry** - Confirms containers stopped/started with automatic retries
- **Retry Logic** - Automatic retries for cloud operations
- **File Locking** - Prevents concurrent operations
- **Signal Handling** - Graceful shutdown with container recovery
- **Dry Run Mode** - Preview operations before execution
- **Comprehensive Logging** - Detailed logs to file and console

## Prerequisites

> **Note:** The installation commands below are for Debian-based distributions (Ubuntu, Debian, etc.) using the `apt` package manager. For other distributions, use your system's package manager or install from source.

### Required: Restic

Restic is the backup engine that creates deduplicated, encrypted snapshots.

📖 **Documentation:** [restic.readthedocs.io](https://restic.readthedocs.io/)

```bash
# Install restic (Debian/Ubuntu)
sudo apt-get install restic

# Initialize your restic repository (first time only)
export RESTIC_PASSWORD="your-secure-password"
restic init -r /path/to/your/restic-repo

# Verify it works
restic -r /path/to/your/restic-repo snapshots
```

**Important restic configuration:**
- `RESTIC_REPOSITORY` - Path to your restic repo (local path, SFTP, S3, etc.)
- `RESTIC_PASSWORD` - Repository encryption password (store securely!)
- Alternatively use `RESTIC_PASSWORD_FILE` or `RESTIC_PASSWORD_COMMAND`

### Required: Docker

```bash
# Debian/Ubuntu
sudo apt-get install docker.io docker-compose-v2
```

### Optional: Rclone (for cloud sync)

Rclone enables Stage 2 (upload) and Stage 3 (restore) cloud operations.

📖 **Documentation:** [rclone.org/docs](https://rclone.org/docs/)

```bash
# Install rclone (Debian/Ubuntu)
sudo apt-get install rclone

# Configure a cloud remote (interactive wizard)
rclone config

# Example: Configure Backblaze B2
# 1. Run: rclone config
# 2. Choose 'n' for new remote
# 3. Name it (e.g., 'backblaze')
# 4. Choose provider (e.g., 'b2' for Backblaze)
# 5. Enter your account ID and application key
# 6. Accept defaults for remaining options

# Verify your remote works
rclone lsd backblaze:

# Test connectivity to your backup bucket
rclone ls backblaze:your-bucket-name
```

**Common rclone remotes:**
- Backblaze B2: `rclone config` → type `b2`
- AWS S3: `rclone config` → type `s3`
- Google Drive: `rclone config` → type `drive`
- SFTP: `rclone config` → type `sftp`

### Build from Source (optional)

```bash
go build -o bin/backup-tui ./cmd/backup-tui/
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
│   ├── Toggle directories on/off
│   ├── Add external paths (X key)
│   └── Remove external paths (D key)
├── 5. Status & Logs
├── Q. Quick Backup (shortcut)
├── S. Quick Status (shortcut)
└── 0. Exit
```

## Directory Management

The tool automatically discovers Docker stacks in your `DOCKER_STACKS_DIR`. You can also add **external paths** - Docker compose stacks located anywhere on your filesystem.

### Adding External Paths

1. Open the TUI: `./bin/backup-tui`
2. Go to **Directory Management** (option 4)
3. Press **X** to open the file picker
4. Navigate to your Docker stack directory (must contain `docker-compose.yml`)
5. Press **A** to add the current directory

Alernatively, manually add full paths to directories containing docker compose files to your dirlist file. See below. 

**File picker controls:**
- `↑/↓` - Navigate file list
- `Enter` - Enter directory
- `Backspace` - Go up a directory level
- `A` - Add current directory as external path
- `ESC` - Cancel

### Managing Directories

In the Directory Management screen:
- `↑/↓` - Navigate list
- `Enter/Space` - Toggle backup on/off
- `S` - Save changes
- `A` - Enable all
- `N` - Disable all
- `X` - Add external path
- `D` - Remove external path (external paths only)

External paths are marked with `[EXT]` in the directory list.

### Dirlist File Format

The `dirlist` file stores your backup selections. 
This file is auto-generated/updated when you use the directory management tool in the TUI:

```ini
# Discovered directories (relative to DOCKER_STACKS_DIR)
my-stack=true
another-stack=false

# External directories (absolute paths)
/home/user/projects/docker-app=true
/opt/custom-stack=true
```

## Cron Example

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup-tui backup -v >> /var/log/backup.log 2>&1

# Weekly cloud sync on Sundays at 3 AM
0 3 * * 0 /path/to/backup-tui sync -v >> /var/log/backup-sync.log 2>&1
```

## Documentation

For detailed reference, see:
- **[Configuration Guide](docs/CONFIGURATION.md)** - All config options, password methods, example configs
- **[Usage Guide](docs/USAGE.md)** - CLI commands, workflows, troubleshooting
- **[Architecture](docs/ARCHITECTURE.md)** - Technical internals, container management, security model

---

**Self-Contained Design**: All configuration and data files are kept within this directory for complete portability.
