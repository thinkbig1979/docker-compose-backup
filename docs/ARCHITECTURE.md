# 3-Stage Backup System Architecture

## Overview

The Docker Stack 3-Stage Backup System implements a hybrid backup approach that combines the speed of local backups with the safety of cloud storage. All functionality is provided by a single unified Go binary: `backup-tui-go`.

## Architecture Diagram

```
Docker Stacks → Stage 1 → Stage 2 → Stage 3
     ↓            ↓         ↓         ↓
[docker-stacks] → [restic] → [cloud] → [restore]
                    ↑         ↑         ↑
                 local fast   remote    disaster
                  backups    safety    recovery
```

## Unified Binary: backup-tui-go

The entire backup system is managed by a single Go binary that provides:
- Interactive TUI mode for menu-driven operations
- Headless CLI mode for scripting and cron jobs
- All three backup stages in one tool

```bash
./bin/backup-tui-go              # Interactive TUI
./bin/backup-tui-go backup       # Stage 1: Local backup
./bin/backup-tui-go sync         # Stage 2: Cloud sync
./bin/backup-tui-go restore      # Stage 3: Cloud restore
```

## Stage Details

### Stage 1: Local Restic Backup
- **Command**: `backup-tui-go backup`
- **Technology**: restic backup engine
- **Features**:
  - Selective directory processing via `dirlist`
  - Sequential Docker stack management
  - Smart state tracking (only affects running stacks)
  - Post-backup verification
  - Retention policy enforcement
  - Dry-run mode for testing

### Stage 2: Cloud Synchronization
- **Command**: `backup-tui-go sync`
- **Technology**: rclone cloud sync
- **Features**:
  - Syncs entire restic repository to cloud
  - Retry logic with exponential backoff
  - Bandwidth limiting support
  - Progress reporting
  - Multiple cloud provider support

### Stage 3: Disaster Recovery
- **Command**: `backup-tui-go restore [PATH]`
- **Technology**: rclone cloud restore
- **Features**:
  - Restores restic repository from cloud
  - Post-restore verification
  - Integrity checking
  - Foundation for data restoration

## Go Package Structure

```
internal/
├── config/      # INI-style configuration parser
├── backup/      # Docker and restic operations
│   ├── docker.go    # Smart stop/start, state tracking
│   ├── restic.go    # Backup, verify, retention
│   └── backup.go    # Orchestration service
├── cloud/       # rclone sync and restore
│   ├── sync.go      # Upload with retry logic
│   └── restore.go   # Download with verification
├── dirlist/     # Directory discovery and management
│   ├── discover.go  # Find Docker compose dirs
│   └── manager.go   # CRUD operations on dirlist
├── tui/         # Terminal user interface
│   ├── app.go       # Main TUI application
│   └── dirlist.go   # Directory selection screen
└── util/        # Shared utilities
    ├── exec.go      # Command execution with timeout
    ├── lock.go      # File locking, PID management
    └── log.go       # Structured logging
```

## Data Flow

```
1. Discovery Phase
   ├── Scan DOCKER_STACKS_DIR for compose directories
   ├── Load dirlist preferences
   └── Identify enabled directories

2. Backup Phase (Stage 1)
   ├── Store initial Docker stack states
   ├── For each enabled directory:
   │   ├── Smart stop (only if running)
   │   ├── Create restic backup with tags
   │   ├── Verify backup (optional)
   │   ├── Apply retention policy (optional)
   │   └── Smart restart (only if was running)
   └── Generate backup summary

3. Cloud Sync Phase (Stage 2)
   ├── Test remote connectivity
   ├── Sync repository to cloud with retry
   └── Report sync status

4. Recovery Phase (Stage 3)
   ├── Test remote connectivity
   ├── Restore repository from cloud
   ├── Verify restored data
   └── Report next steps
```

## Configuration

INI-style configuration with sections:

```ini
[docker]
DOCKER_STACKS_DIR=/opt/docker-stacks
DOCKER_TIMEOUT=300

[local_backup]
RESTIC_REPOSITORY=/mnt/backup/restic-repo
RESTIC_PASSWORD=...
AUTO_PRUNE=true

[cloud_sync]
RCLONE_REMOTE=backblaze
RCLONE_PATH=/backup/restic
```

Legacy flat format is also supported for backwards compatibility.

## Security Model

- **Configuration Protection**: `backup.conf` has 0600 permissions
- **Password Handling**: Supports password file or command (avoids env vars)
- **State Isolation**: Each backup operation is atomic
- **Error Boundaries**: Failures in one directory don't affect others
- **Signal Handling**: Graceful shutdown with stack recovery
- **PID Management**: Prevents concurrent execution
- **File Locking**: Prevents dirlist corruption

## Key Features

- **Single Binary**: One tool for all operations
- **TUI + CLI**: Interactive and scripted modes
- **Sequential Processing**: Controlled resource usage
- **Smart Docker Management**: Only stops running containers
- **Retry Logic**: Automatic retries for cloud operations
- **Incremental Backups**: restic deduplication
- **Progress Monitoring**: Real-time status reporting
