# Docker Stack 3-Stage Backup System

A comprehensive 3-stage backup solution for Docker compose stacks using restic with cloud synchronization.

## Quick Start

```bash
# 1. Launch the Text User Interface
./bin/backup-tui.sh

# 2. Or run backup directly  
./bin/docker-backup.sh

# 3. Or run individual stages
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
├── utils/                 # Maintenance utilities
├── docs/                  # Documentation
├── testing/               # Test suite
├── docker-stacks/         # Your Docker compose directories
└── logs/                  # Runtime logs
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

## Features

- **Text User Interface (TUI)** - Unified management interface
- **Selective Backup** - Choose which Docker stacks to backup
- **Sequential Processing** - Safe, controlled operations
- **Smart Docker Management** - Only affects running stacks
- **Comprehensive Logging** - Detailed progress and error tracking
- **Dry Run Mode** - Test operations without changes
- **Signal Handling** - Graceful shutdown and cleanup

## Prerequisites

```bash
sudo apt-get install dialog rclone restic docker.io
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

---

**Self-Contained Design**: All configuration and data files are kept within this directory for complete portability.