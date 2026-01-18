# Manage Dirlist - Functional Specification

## Overview

A TUI (Terminal User Interface) tool for managing a directory list file (`dirlist`) that controls which Docker Compose directories are included in backups.

## Purpose

- Discover Docker Compose directories in a configured backup directory
- Allow users to enable/disable directories for backup via an interactive checklist
- Persist selections to a `dirlist` file
- Synchronize the dirlist with actual directories (prune removed, add new)

## File Locations

All paths are relative to the executable location:

| File | Path | Description |
|------|------|-------------|
| Config | `../config/backup.conf` | Configuration file with BACKUP_DIR |
| Dirlist | `../dirlist` | Output file with directory selections |
| Lock | `../locks/dirlist.lock` | Lock file for concurrent access |

Environment variable `BACKUP_CONFIG` can override the config file path.

## Configuration File Format

The `backup.conf` file uses `KEY=VALUE` format:

```
# Comments start with #
BACKUP_DIR=/opt/docker-stacks
```

Required keys:
- `BACKUP_DIR` - Path to directory containing Docker Compose subdirectories

## Dirlist File Format

```
# Comments start with #
directory-name=true
another-directory=false
```

- Each line: `<directory-name>=<enabled>`
- `enabled` is `true` or `false`
- Lines starting with `#` are comments
- Empty lines are ignored

## Directory Discovery

A directory is considered a "Docker Compose directory" if it:
1. Is a direct subdirectory of BACKUP_DIR
2. Is not hidden (doesn't start with `.`)
3. Contains one of:
   - `docker-compose.yml`
   - `docker-compose.yaml`
   - `compose.yml`
   - `compose.yaml`

## Directory Name Validation

Valid directory names:
- Contain only: `a-z`, `A-Z`, `0-9`, `.`, `_`, `-`
- Do not start with `.` (hidden)
- Are not just dots (`.`, `..`, `...`)

## Operating Modes

### 1. Interactive Mode (default)

```bash
manage-dirlist
```

1. Load configuration
2. Discover Docker Compose directories
3. Load existing dirlist (if exists)
4. Show checklist dialog with all directories
5. Show confirmation dialog with summary
6. Save selections to dirlist file

### 2. Prune Mode

```bash
manage-dirlist --prune
manage-dirlist -p
```

1. Synchronize dirlist with actual directories
2. Then show interactive interface

### 3. Prune-Only Mode

```bash
manage-dirlist --prune-only
```

1. Synchronize dirlist with actual directories
2. Exit (no interactive interface)

Synchronization:
- Remove entries for directories that no longer exist
- Add entries for new directories (default: `false`)

### 4. Help Mode

```bash
manage-dirlist --help
manage-dirlist -h
```

Show usage information and exit.

## TUI Screens

### Screen 1: Directory Checklist

```
┌─────────── Backup Directory Management ───────────┐
│                                                    │
│ Select directories to include in backup:          │
│                                                    │
│ Use SPACE to toggle, ENTER to confirm, ESC cancel │
│                                                    │
│ [X] nginx-proxy     Docker compose directory      │
│ [ ] postgres-db     Docker compose directory      │
│ [X] redis-cache     Docker compose directory      │
│                                                    │
│         < OK >              < Cancel >            │
└────────────────────────────────────────────────────┘
```

- Directories sorted alphabetically
- Pre-checked based on existing dirlist or default to checked for new
- SPACE toggles selection
- ENTER confirms
- ESC cancels

### Screen 2: Confirmation Dialog

```
┌─────────────── Confirm Changes ───────────────────┐
│                                                    │
│ Directory Backup Settings Summary:                 │
│                                                    │
│ ENABLED directories (will be backed up):          │
│   ✓ nginx-proxy                                   │
│   ✓ redis-cache                                   │
│                                                    │
│ DISABLED directories (will be skipped):           │
│   ✗ postgres-db                                   │
│                                                    │
│ Total: 2 enabled, 1 disabled                      │
│                                                    │
│ ⚠ Changes detected - dirlist file will be updated │
│                                                    │
│ Do you want to save these settings?               │
│                                                    │
│         < Yes >              < No >               │
└────────────────────────────────────────────────────┘
```

## Exit Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Operation completed successfully |
| 1 | CONFIG_ERROR | Configuration file missing or invalid |
| 2 | DIALOG_ERROR | TUI library not available |
| 3 | USER_CANCEL | User cancelled operation |
| 6 | LOCK_ERROR | Failed to acquire lock |

## Concurrency

- Uses file locking before writing dirlist
- Lock timeout: 30 seconds
- Lock file: `../locks/dirlist.lock`
- Lock directory created if missing

## Output Messages

Colored console output:
- `[INFO]` (blue) - Informational messages
- `[SUCCESS]` (green) - Success messages
- `[WARNING]` (yellow) - Warning messages
- `[ERROR]` (red) - Error messages (to stderr)

## Terminal Handling

- Clean up terminal on exit (normal, interrupt, terminate)
- Restore cursor visibility
- Reset terminal attributes
- Only clear screen on non-successful exits (preserve success messages)

## Error Handling

1. **Config file not found** - Exit with CONFIG_ERROR
2. **BACKUP_DIR not in config** - Exit with CONFIG_ERROR
3. **BACKUP_DIR doesn't exist** - Exit with CONFIG_ERROR
4. **No Docker Compose directories found** - Show warning, exit SUCCESS
5. **Lock acquisition fails** - Exit with LOCK_ERROR
6. **File write fails** - Exit with CONFIG_ERROR

## Atomic File Operations

- Write to temporary file first
- Move temp file to final location (atomic on same filesystem)
- Set permissions to 600 (owner read/write only)
