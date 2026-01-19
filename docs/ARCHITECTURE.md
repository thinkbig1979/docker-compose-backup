# 3-Stage Backup System Architecture

## Overview

The Docker Stack 3-Stage Backup System implements a hybrid backup approach that combines the speed of local backups with the safety of cloud storage. All functionality is provided by a single unified Go binary: `backup-tui`.

## Architecture Diagram

```
Docker Stacks → Stage 1 → Stage 2 → Stage 3
     ↓            ↓         ↓         ↓
[docker-stacks] → [restic] → [cloud] → [restore]
                    ↑         ↑         ↑
                 local fast   remote    disaster
                  backups    safety    recovery
```

## Unified Binary: backup-tui

The entire backup system is managed by a single Go binary that provides:
- Interactive TUI mode for menu-driven operations
- Headless CLI mode for scripting and cron jobs
- All three backup stages in one tool

```bash
./bin/backup-tui                 # Interactive TUI
./bin/backup-tui backup          # Stage 1: Local backup
./bin/backup-tui sync            # Stage 2: Cloud sync
./bin/backup-tui restore         # Stage 3: Cloud restore
```

## Stage Details

### Stage 1: Local Restic Backup
- **Command**: `backup-tui backup`
- **Technology**: restic backup engine
- **Features**:
  - Selective directory processing via `dirlist`
  - Sequential Docker stack management with `docker compose down/up -d`
  - Smart state tracking (only affects running stacks)
  - Defensive StateUnknown handling (restarts if state uncertain)
  - Post-backup verification with retry logic
  - Retention policy enforcement
  - Dry-run mode for testing

### Stage 2: Cloud Synchronization
- **Command**: `backup-tui sync`
- **Technology**: rclone cloud sync
- **Features**:
  - Syncs entire restic repository to cloud
  - Retry logic with exponential backoff
  - Bandwidth limiting support
  - Progress reporting
  - Multiple cloud provider support

### Stage 3: Disaster Recovery
- **Command**: `backup-tui restore [PATH]`
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
   │   ├── Smart stop with `docker compose down` (only if running)
   │   ├── Verify containers stopped (with retry)
   │   ├── Create restic backup with tags
   │   ├── Verify backup (optional)
   │   ├── Apply retention policy (optional)
   │   ├── Smart restart with `docker compose up -d` (only if was running)
   │   └── Verify containers started (with retry)
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

## Docker Container Management

The backup system uses a robust approach to container lifecycle management:

### Stop/Start Strategy: down/up -d

Instead of `docker compose stop/start`, the system uses:
- **Stop**: `docker compose down --timeout N` - Fully removes containers
- **Start**: `docker compose up -d` - Recreates containers from compose file

**Benefits**:
- Cleaner container state (no orphaned containers)
- More reliable restarts (fresh container creation)
- Handles compose file changes between backup runs
- Works correctly even if containers were in an inconsistent state

### State Tracking

The system tracks four container states:
- **StateRunning**: Stack has running containers (will be stopped/restarted)
- **StateStopped**: Stack has no running containers (skipped)
- **StateNotFound**: No containers exist for stack (skipped)
- **StateUnknown**: Unable to determine state (restarted defensively)

The **defensive StateUnknown handling** ensures containers are restarted even when the initial state check fails, preventing accidental container outages.

### Verification with Retry

Both stop and start operations include verification loops:
1. Execute the docker compose command
2. Wait 2 seconds for containers to settle
3. Check container status (up to 3 attempts with 3-second intervals)
4. Report success or failure

### Command Timeout with Process Group Kill

External commands (docker, restic, rclone) run with configurable timeouts:
- Commands are started in a **new process group** (`Setpgid: true`)
- On timeout, the **entire process group is killed** (`SIGKILL -pgid`)
- This ensures child processes (spawned by docker compose) are also terminated
- Prevents hung processes from blocking the backup indefinitely

## Security Model

- **Configuration Protection**: `config.ini` has 0600 permissions
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
