# External Docker Stack Paths - Session Handoff

## Feature Overview

Added the ability to backup Docker stacks from arbitrary filesystem locations, not just from `DOCKER_STACKS_DIR`. Users can add external paths via TUI file picker (X key) or manually edit the dirlist file with absolute paths.

## Branch

`feature/external-paths-support` - 3 commits pushed to origin

## Implementation Status: COMPLETE ✓

All phases implemented and tested:

### Phase 1: Dirlist Manager (`internal/dirlist/`)

**manager.go:**
- Added `Entry` struct with `Path`, `Enabled`, `IsExternal` fields
- Updated `Manager.entries` from `map[string]bool` to `map[string]*Entry`
- `Load()` detects external paths (starting with `/`) and creates appropriate entries
- `Save()` writes discovered and external entries in separate sections with comments
- `Sync()` preserves external entries (only syncs discovered ones)
- New methods: `GetEntry()`, `GetFullPath()`, `AddExternal()`, `RemoveExternal()`, `GetSelections()`, `GetAllIdentifiers()`

**discover.go:**
- Added `ValidateAbsolutePath()` - validates path is absolute, exists, is directory, has compose file

**external_test.go:**
- Comprehensive unit tests for all external path functionality (8 tests, all passing)

### Phase 2: Backup Service (`internal/backup/backup.go`)

- `processBackups()` uses `s.dirlist.GetFullPath()` instead of `filepath.Join()`
- `processDirectory()` uses `GetEntry()` to check if path is external
- External paths get tag suffix `-external` for restic snapshots
- `cleanup()` uses `GetFullPath()`

### Phase 3: TUI (`internal/tui/`)

**messages.go:**
- Added `ScreenFilePicker` constant

**app.go:**
- Added `filepicker` import from `github.com/charmbracelet/bubbles/filepicker`
- Added model fields: `filepicker`, `filePickerActive`, `filePickerErr`
- Added `os` import for `UserHomeDir()`
- Key handlers:
  - `X` - opens file picker to add external path
  - `D` - removes external entry (only works on external entries)
- New functions:
  - `openFilePicker()` - initializes file picker starting from home directory
  - `handleFilePickerKey()` - handles navigation and selection
  - `viewFilePicker()` - renders file picker screen with current directory
  - `refreshDirlistView()` - updates TUI state from in-memory dirlist without reloading from file
- Updated `viewDirlist()` to show `[EXT]` marker for external entries
- Updated `updateActiveScreen()` to handle `ScreenFilePicker` case
- Updated help text with X/D key hints

## New Dirlist Format

```ini
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup

# Discovered directories (relative to DOCKER_STACKS_DIR)
stack-name=true
another-stack=false

# External directories (absolute paths)
/opt/other-location/my-stack=true
/home/user/docker/project=false
```

Detection logic: Entry starting with `/` = external absolute path

## Bugs Fixed During Testing

1. **File picker showing "No Files Found"** (commit c76c0e9)
   - Root cause: Starting from "/" had permission issues
   - Fix: Start from user's home directory, set `FileAllowed = true`

2. **File picker not displaying contents** (commit 100a0a1)
   - Root cause: `updateActiveScreen()` didn't handle `ScreenFilePicker`
   - Fix: Added case for `ScreenFilePicker` to call `m.filepicker.Update(msg)`

3. **D key not removing external entries** (commit 100a0a1)
   - Root cause: `initDirlist()` reloads from file, undoing in-memory changes
   - Fix: Created `refreshDirlistView()` that updates TUI state without reloading from file

## Testing Done

### Unit Tests
```bash
go test -v ./internal/dirlist/...
# All 8 tests pass:
# - SyncDiscoveredDirectories
# - AddExternalPath
# - GetFullPath
# - SaveAndReload
# - SyncPreservesExternal
# - RemoveExternal
# - ValidateAbsolutePath
# - DirlistFileFormat
```

### TUI Screenshot Tests (using tui-screenshot tool)

```bash
# Main menu - WORKS
./tui-screenshot/bin/tui-screenshot -delay 1s -rows 30 -cols 100 -- ./bin/backup-tui

# Directory Management screen - WORKS
./tui-screenshot/bin/tui-screenshot -delay 1s -rows 30 -cols 100 -keys "4" -- ./bin/backup-tui

# File picker - WORKS
./tui-screenshot/bin/tui-screenshot -delay 2s -rows 30 -cols 100 -keys "4 x" -- ./bin/backup-tui

# External path display with [EXT] marker - WORKS
# (after manually adding external path to dirlist)

# D key to remove external - WORKS
./tui-screenshot/bin/tui-screenshot -delay 1s -rows 30 -cols 100 -keys "4 d" -- ./bin/backup-tui

# Save after remove - WORKS
./tui-screenshot/bin/tui-screenshot -delay 1s -rows 30 -cols 100 -keys "4 d s" -- ./bin/backup-tui
```

## Not Yet Tested

1. **End-to-end file picker add flow** - navigating through file picker to select a directory with compose file and verifying it gets added
2. **Actual backup with external paths** - running `backup --dry-run` with external paths enabled
3. **Paths with spaces** - external paths containing spaces in directory names

## Test Data Setup

```bash
# Create test external stack
mkdir -p /tmp/external-test-stack
cat > /tmp/external-test-stack/docker-compose.yml << 'EOF'
version: '3.8'
services:
  test:
    image: alpine:latest
    command: sleep infinity
EOF

# Add to dirlist manually for testing
echo "/tmp/external-test-stack=true" >> dirlist
```

## Files Modified

| File | Changes |
|------|---------|
| `internal/dirlist/manager.go` | Entry struct, external path methods |
| `internal/dirlist/discover.go` | ValidateAbsolutePath function |
| `internal/dirlist/external_test.go` | NEW - unit tests |
| `internal/backup/backup.go` | GetFullPath usage, external tags |
| `internal/tui/messages.go` | ScreenFilePicker constant |
| `internal/tui/app.go` | File picker, [EXT] markers, X/D keys, refreshDirlistView |
| `go.mod` / `go.sum` | Added dustin/go-humanize dependency (filepicker) |
| `bin/backup-tui` | Rebuilt binary |

## Commands for Next Session

```bash
# Build
cd "/home/edwin/development/backup script"
go build -o bin/backup-tui ./cmd/backup-tui

# Run tests
go test -v ./internal/dirlist/...

# Run linter
golangci-lint run ./...

# Test TUI with screenshot tool
./tui-screenshot/bin/tui-screenshot -delay 1s -rows 30 -cols 100 -keys "4" -- ./bin/backup-tui

# Test backup dry run
./bin/backup-tui backup --dry-run -v
```

## Remaining Work (Phase 4 - Polish)

See `Supporting-Docs/external-paths-tui-spec.md` for detailed TUI spec.

Potential improvements:
- Confirmation dialog before removing external path
- Show full path on hover/selection in dirlist
- Better error handling in file picker
- Test paths with spaces
- Integration tests with actual backup
