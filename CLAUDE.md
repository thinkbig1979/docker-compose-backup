# Backup Script Project

## Project Overview
A Docker Stack 3-Stage Backup System with:
- **Stage 1**: Local backup using restic (stop containers → backup → restart)
- **Stage 2**: Cloud sync upload using rclone
- **Stage 3**: Cloud restore download using rclone

## Development Tools
- **Go LSP**: Available for code navigation (goToDefinition, findReferences, hover, etc.)
- **tview**: TUI library for interactive interface
- **restic**: Backup tool for local snapshots
- **rclone**: Cloud sync tool for remote storage

## Project Structure
```
backup script/
├── cmd/
│   ├── backup-tui/              # NEW: Unified Go TUI (in progress)
│   │   └── main.go
│   ├── docker-backup/           # Legacy Go binary (to deprecate)
│   └── manage-dirlist/          # Legacy Go binary (to deprecate)
├── internal/                    # NEW: Shared Go packages
│   ├── config/                  # INI config parser
│   ├── backup/                  # Docker + restic operations
│   ├── cloud/                   # rclone sync/restore
│   ├── dirlist/                 # Directory discovery & management
│   ├── tui/                     # TUI screens and navigation
│   └── util/                    # Exec, lock, logging utilities
├── scripts/
│   ├── rclone_backup.sh         # Legacy (to deprecate)
│   └── rclone_restore.sh        # Legacy (to deprecate)
├── config/
│   ├── config.ini               # Main configuration
│   └── config.ini.template      # Config template
├── bin/
│   └── backup-tui-go            # Built unified binary
├── logs/                        # Runtime logs
├── locks/                       # Lock files
├── dirlist                      # Directory enable/disable list
├── go.mod                       # Go module (project root)
└── CLAUDE.md                    # This file
```

## Current Migration: Unified Go TUI

### Goal
Consolidate all bash scripts and separate Go binaries into a single `backup-tui-go` binary.

### New Config Format (INI-style with sections)
```ini
[docker]
DOCKER_STACKS_DIR=/opt/docker-stacks
DOCKER_TIMEOUT=300

[local_backup]
RESTIC_REPOSITORY=/mnt/backup/restic-repo
RESTIC_PASSWORD=your-password
KEEP_DAILY=7
KEEP_WEEKLY=4

[cloud_sync]
RCLONE_REMOTE=backblaze
RCLONE_PATH=/backup/restic
TRANSFERS=4
```

### CLI Interface
```bash
backup-tui-go                    # TUI mode (default)
backup-tui-go backup             # Headless backup
backup-tui-go backup --dry-run   # Dry run
backup-tui-go sync               # Cloud sync
backup-tui-go restore [PATH]     # Restore from cloud
backup-tui-go status             # Show status
backup-tui-go validate           # Validate config
```

### Implementation Phases
1. ✅ Foundation: go.mod, config parser, utilities
2. ✅ Backup Service: docker ops, restic commands
3. ✅ Cloud Operations: rclone sync/restore
4. ✅ TUI: tview screens, menu navigation
5. ✅ CLI & Integration: flag parsing, headless commands

## Key Decisions
| Decision | Choice |
|----------|--------|
| TUI library | tview (already used) |
| Config format | INI-style with sections |
| Source dir var | `DOCKER_STACKS_DIR` (was `BACKUP_DIR`) |
| Existing binaries | Deprecate after migration |

## Code Patterns
- Use `context.WithTimeout` for all external commands
- Atomic file writes (temp file → rename)
- File locking with `syscall.Flock`
- Smart container management (only restart if was running)

## Files to Delete After Migration
- `cmd/manage-dirlist/`
- `cmd/docker-backup/`
- `bin/backup-tui.sh`
- `scripts/rclone_backup.sh`
- `scripts/rclone_restore.sh`
