# Docker Stack 3-Stage Backup System

A comprehensive 3-stage backup solution for Docker compose stacks using restic with cloud synchronization.

## Quick Start

```bash
# 1. Run installation
./install.sh

# 2. Launch the Text User Interface
./bin/backup-tui.sh

# 3. Or run backup directly  
./bin/docker-backup.sh

# 4. Or run individual stages
./scripts/rclone_backup.sh    # Cloud sync
./scripts/rclone_restore.sh   # Cloud restore
```

## 3-Stage Architecture

**Stage 1: Local Restic Backup** → **Stage 2: Cloud Sync** → **Stage 3: Disaster Recovery**

1. `docker-backup.sh` - Creates local restic backups of Docker stacks
2. `rclone_backup.sh` - Syncs local repository to cloud storage  
3. `rclone_restore.sh` - Restores repository from cloud

## Repository Structure

```
├── bin/                    # Main executable scripts
│   ├── backup-tui.sh      # Text User Interface (recommended)
│   ├── docker-backup.sh   # Stage 1: Local backup
│   └── manage-dirlist.sh  # Directory management TUI
├── scripts/               # Utility scripts  
│   ├── rclone_backup.sh   # Stage 2: Cloud sync
│   └── rclone_restore.sh  # Stage 3: Cloud restore
├── config/                # Configuration files
│   ├── backup.conf        # Main configuration (copy from template)
│   └── backup.conf.template # Template configuration
├── lib/                   # Shared libraries
│   └── common.sh          # Common functions (logging, locking, validation)
├── locks/                 # Lock files for concurrent access prevention
├── utils/                 # Maintenance utilities
├── docs/                  # Documentation
├── testing/               # Test suite
├── logs/                  # Runtime logs
└── dirlist                # Directory selection for backups
```

## Configuration

1. Copy configuration template:
   ```bash
   cp config/backup.conf.template config/backup.conf
   ```

2. Edit `config/backup.conf` with your settings:
   ```bash
   BACKUP_DIR=/path/to/docker-stacks
   RESTIC_REPOSITORY=/path/to/restic/repo
   RESTIC_PASSWORD=your-password
   ```

3. Configure rclone for cloud storage (optional):
   ```bash
   rclone config
   ```

## Text User Interface (TUI)

The TUI provides a comprehensive interface for managing all backup operations:

```bash
./bin/backup-tui.sh
```

### TUI Features

- **Breadcrumb Navigation** - Always know where you are in the menu hierarchy
- **Quick Shortcuts** - Press `Q` for Quick Backup, `S` for Quick Status from main menu
- **Auto-Sync Detection** - Automatically detects when directories have been added/removed
- **Detailed Validation** - Comprehensive prerequisite checks with detailed feedback
- **Directory Management** - Enable/disable directories, bulk operations, import/export

### Main Menu Options

| Option | Description |
|--------|-------------|
| Stage 1: Docker Stack Backup | Local restic backup operations |
| Stage 2: Cloud Sync | Upload backups to cloud storage |
| Stage 3: Cloud Restore | Download and restore from cloud |
| Configuration Management | Edit configs, manage rclone remotes |
| Directory List Management | Select which directories to backup |
| Monitoring & Status | View system status and resources |
| System Health Check | Verify all prerequisites |
| View Logs | Access backup and sync logs |

### Directory Management

The TUI includes comprehensive directory management:

- **Auto-Sync Detection** - Shows `[!]` indicator when directories are out of sync
- **Bulk Operations** - Enable/disable all, pattern matching, templates
- **Import/Export** - Save and restore directory configurations
- **Validation** - Check dirlist file format and content

## Directory List Management (Standalone)

Manage backup directories independently:

```bash
# Interactive mode
./bin/manage-dirlist.sh

# Sync directories before showing interface
./bin/manage-dirlist.sh --prune

# Only sync, no interface
./bin/manage-dirlist.sh --prune-only
```

## Features

- **Text User Interface (TUI)** - Unified management interface with breadcrumb navigation
- **Selective Backup** - Choose which Docker stacks to backup via dirlist
- **Auto-Sync Detection** - Automatically detects new/removed directories
- **File Locking** - Prevents concurrent modifications to configuration
- **Sequential Processing** - Safe, controlled operations
- **Smart Docker Management** - Only affects running stacks
- **Comprehensive Logging** - Detailed progress and error tracking
- **Dry Run Mode** - Test operations without changes
- **Signal Handling** - Graceful shutdown and cleanup
- **Detailed Validation** - Prerequisite checks with itemized feedback

## Shared Library

The `lib/common.sh` library provides shared functionality:

- **Logging** - Consistent log format with levels (INFO, WARN, ERROR, DEBUG)
- **Input Validation** - Path sanitization, directory name validation
- **File Locking** - Prevent concurrent access with `flock`
- **Temp File Management** - Automatic cleanup of temporary files
- **Configuration Parsing** - Secure config file loading
- **Password Security** - Safe password handling (file, command, or direct)

## Prerequisites

```bash
# Required
sudo apt-get install dialog restic docker.io

# Optional (for cloud sync)
sudo apt-get install rclone
```

## Documentation

- Full documentation: `docs/README.md`
- Test suite: `testing/README.md`
- Configuration help: `config/backup.conf.template`

## Testing

```bash
cd testing/scripts
./run-tests.sh --all      # Run complete test suite
./run-tests.sh --docker   # Run tests in Docker environment
```

## Keyboard Shortcuts (TUI)

| Key | Action |
|-----|--------|
| `Q` | Quick Backup (from main menu) |
| `S` | Quick Status (from main menu) |
| `Space` | Toggle selection in checklists |
| `Enter` | Confirm selection |
| `Esc` | Cancel / Go back |
| `Tab` | Move between buttons |
| Arrow keys | Navigate menus |

---

**Self-Contained Design**: All configuration and data files are kept within this directory for complete portability.
