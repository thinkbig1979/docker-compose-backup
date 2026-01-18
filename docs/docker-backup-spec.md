# Docker Backup - Functional Specification

## Overview

A Docker compose stack backup utility using restic. Performs selective, sequential backups with smart container management (only stops running stacks, restores original state after backup).

## Core Workflow

```
1. Load Configuration
2. Pre-flight checks (disk space, repository health)
3. Scan directories for Docker compose projects
4. Load dirlist (which directories to backup)
5. Store initial stack states (running/stopped)
6. For each enabled directory:
   a. Smart stop (only if running)
   b. Backup with restic
   c. Verify backup (optional)
   d. Apply retention policy (optional)
   e. Smart start (only if was running)
7. Generate health report
```

## File Locations

| File | Path | Description |
|------|------|-------------|
| Config | `../config/backup.conf` | Main configuration |
| Dirlist | `../dirlist` | Directory enable/disable list |
| Log | `../logs/docker_backup.log` | Main log file |
| PID | `../logs/docker_backup.pid` | Lock file for single instance |
| Locks | `../locks/` | Directory for file locks |

## Configuration File (backup.conf)

### Required Settings
```
BACKUP_DIR=/opt/docker-stacks       # Directory containing compose projects
RESTIC_REPOSITORY=/path/to/repo     # Restic repository (local, sftp://, s3://, etc.)
RESTIC_PASSWORD=secret              # Repository password
```

### Optional Settings
```
# Timeouts
BACKUP_TIMEOUT=3600                 # Backup timeout in seconds (default: 3600)
DOCKER_TIMEOUT=30                   # Docker command timeout (default: 30)

# Identification
HOSTNAME=my-server                  # Custom hostname for snapshots

# Retention Policy
KEEP_DAILY=7                        # Keep N daily snapshots
KEEP_WEEKLY=4                       # Keep N weekly snapshots
KEEP_MONTHLY=12                     # Keep N monthly snapshots
KEEP_YEARLY=3                       # Keep N yearly snapshots
AUTO_PRUNE=false                    # Auto-apply retention after backup

# Security
ENABLE_PASSWORD_FILE=false          # Use password file instead
RESTIC_PASSWORD_FILE=/path/to/file  # Password file path
ENABLE_PASSWORD_COMMAND=false       # Use command for password
RESTIC_PASSWORD_COMMAND="cmd"       # Password command

# Verification
ENABLE_BACKUP_VERIFICATION=false    # Verify backups after creation
VERIFICATION_DEPTH=files            # metadata|files|data

# Resource Monitoring
MIN_DISK_SPACE_MB=1024              # Minimum free space required
CHECK_SYSTEM_RESOURCES=false        # Monitor CPU/memory
MEMORY_THRESHOLD_MB=512             # Warn if free memory below
LOAD_THRESHOLD=80                   # Warn if load above %

# Performance
ENABLE_PERFORMANCE_MODE=false       # Add restic optimization flags
ENABLE_DOCKER_STATE_CACHE=false     # Cache Docker states

# Logging
ENABLE_JSON_LOGGING=false           # JSON structured logging
ENABLE_PROGRESS_BARS=false          # Show progress bars
ENABLE_METRICS_COLLECTION=false     # Collect metrics
```

## Directory Discovery

A directory is a Docker compose project if it:
1. Is a direct subdirectory of BACKUP_DIR
2. Is not hidden (doesn't start with `.`)
3. Contains one of:
   - `docker-compose.yml`
   - `docker-compose.yaml`
   - `compose.yml`
   - `compose.yaml`

## Dirlist File Format

```
# Comments start with #
project-a=true      # Will be backed up
project-b=false     # Will be skipped
```

New directories default to `false` (opt-in).

## Docker Stack Management

### Smart Stop
1. Check if stack was originally running
2. If running: stop containers with `docker compose stop`
3. Wait for graceful shutdown (with timeout)
4. Verify containers are stopped
5. If was stopped: do nothing

### Smart Start
1. Check original state
2. If was running: restart with `docker compose start`
3. If was stopped: leave stopped

### Initial State Tracking
Before any operations, record the state of all enabled stacks:
- `running`: Has running containers
- `stopped`: No running containers
- `not_found`: Directory doesn't exist

## Backup Process

### Restic Backup Command
```bash
restic backup \
  --verbose \
  --tag "docker-backup" \
  --tag "selective-backup" \
  --tag "<dir_name>" \
  --tag "<date>" \
  [--hostname "<hostname>"] \
  [--one-file-system] \           # Performance mode
  [--exclude-caches] \            # Performance mode
  [--exclude-if-present .resticignore] \  # Performance mode
  "<dir_path>"
```

### Backup Verification
Depths:
- `metadata`: Quick check - `restic ls <snapshot>`
- `files`: List files and count - `restic ls <snapshot>`
- `data`: Full integrity - `restic check --read-data <snapshot>`

### Retention Policy
```bash
restic forget \
  --verbose \
  --tag "<dir_name>" \
  [--hostname "<hostname>"] \
  [--keep-daily N] \
  [--keep-weekly N] \
  [--keep-monthly N] \
  [--keep-yearly N] \
  --prune
```

## CLI Interface

```
Usage: docker-backup [OPTIONS]

OPTIONS:
  -v, --verbose         Enable verbose output
  -n, --dry-run        Perform dry run without changes
  -h, --help           Show help message
  --list-backups       List recent snapshots
  --restore-preview DIR Preview restore for directory
  --generate-config    Generate config template
  --validate-config    Validate configuration
  --health-check       Generate health report
```

## Exit Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Operation completed |
| 1 | CONFIG_ERROR | Configuration issue |
| 2 | VALIDATION_ERROR | Validation failed |
| 3 | BACKUP_ERROR | Backup operation failed |
| 4 | DOCKER_ERROR | Docker operation failed |
| 5 | SIGNAL_ERROR | Interrupted by signal |

## Signal Handling

- SIGINT, SIGTERM, SIGHUP: Graceful shutdown
- On interrupt during backup:
  1. Attempt to restart interrupted stack (if was running)
  2. Clean up PID file
  3. Clean up temporary files

## Logging

### Log Levels
- ERROR: Errors (red, stderr)
- WARN: Warnings (yellow, stderr)
- INFO: Information (green)
- DEBUG: Debug details (blue, only with --verbose)
- PROGRESS: Progress updates (cyan)
- RESTIC: Restic output (cyan)

### Log Format
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] message
```

## Security Features

1. **Password Handling**: Never export password to environment (visible via `ps`). Convert to temporary password file.
2. **Input Sanitization**: Validate directory names, block path traversal, dangerous characters
3. **File Permissions**: Warn if config file is world-readable
4. **Single Instance**: PID file prevents concurrent runs

## Health Report

JSON report at `logs/backup_health.json`:
```json
{
  "timestamp": "...",
  "status": "success|partial_failure|unknown",
  "last_run": { ... },
  "repository": { "path": "...", "snapshot_count": N },
  "configuration": { ... },
  "system": { "hostname": "...", "disk_space_mb": N }
}
```

## Pre-flight Checks

1. Check restic is installed
2. Validate repository access
3. Check disk space
4. Repository integrity check (1% sample)
5. Check system resources (optional)
