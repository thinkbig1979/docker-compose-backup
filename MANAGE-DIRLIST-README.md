# Directory List Management TUI Script

## ⚠️ INTEGRATION STATUS

**As of 2025-01-15**: This standalone script functionality has been **fully integrated** into the main backup TUI (`backup-tui.sh`). 

**Recommended Usage**: Use the integrated **Directory List Management** menu in the main TUI for the best user experience with enhanced features including bulk operations, directory statistics, and comprehensive troubleshooting.

**Legacy Support**: This standalone script remains available for backward compatibility and command-line automation.

### 🚀 Enhanced Features in Integrated TUI

The integrated version includes all standalone features plus:
- **Bulk Operations**: Pattern-based enable/disable with templates (Production, Development, Testing)
- **Directory Statistics**: Size analysis and backup optimization insights
- **Import/Export**: Portable directory configuration management
- **Advanced Troubleshooting**: Comprehensive diagnostics and problem resolution
- **Real-time Status**: Backup history integration and last backup dates
- **Performance Optimization**: Handles large directory counts efficiently
- **Atomic Operations**: Safe file operations with automatic rollback

## Overview

The `manage-dirlist.sh` script provides an interactive Text User Interface (TUI) for managing the `.dirlist` file used by the Docker backup script. It allows users to easily enable or disable directories for backup without manually editing the configuration file.

## Features

- **Interactive Dialog Interface**: Uses the `dialog` command for a user-friendly TUI
- **Automatic Directory Discovery**: Scans for Docker compose directories automatically
- **Automatic Synchronization**: Detects and handles directory changes automatically
- **Current Status Display**: Shows which directories are currently enabled/disabled
- **Checkbox Selection**: Easy toggle interface for enabling/disabling directories
- **Confirmation Dialog**: Shows summary of changes before saving
- **Error Handling**: Proper validation and error messages
- **Integration**: Works seamlessly with the existing backup script

### New Synchronization Features

- **Removed Directory Detection**: Automatically removes entries for directories that no longer exist
- **New Directory Detection**: Automatically adds entries for newly discovered directories (defaulted to disabled for safety)
- **Changes Summary**: Shows detailed summary of what directories were added or removed
- **Pruning Options**: Command-line flags for automatic synchronization

## Requirements

- `dialog` command must be installed
- `backup.conf` must exist with valid `BACKUP_DIR` configuration
- Must be run from the backup script directory (or specify `BACKUP_CONFIG` environment variable)

### Installing Dialog

```bash
# Ubuntu/Debian
sudo apt-get install dialog

# CentOS/RHEL
sudo yum install dialog

# Fedora
sudo dnf install dialog
```

## Usage

### Basic Usage

```bash
# Run from the backup script directory
./manage-dirlist.sh

# Automatically synchronize dirlist before showing interface
./manage-dirlist.sh --prune

# Only perform synchronization, skip interactive interface
./manage-dirlist.sh --prune-only

# Or specify custom config location
BACKUP_CONFIG=/path/to/backup.conf ./manage-dirlist.sh

# Show help
./manage-dirlist.sh --help
```

### Synchronization Options

```bash
# Automatic synchronization only (no interactive interface)
./manage-dirlist.sh --prune-only

# Synchronize then show interactive interface
./manage-dirlist.sh --prune

# Example with custom config
BACKUP_CONFIG=/path/to/backup.conf ./manage-dirlist.sh --prune-only
```

### Test Environment Usage

```bash
# Test in the test environment
cd test-env
BACKUP_CONFIG=./test-backup.conf ./manage-dirlist.sh
```

## How It Works

1. **Configuration Loading**: Reads `backup.conf` to get the `BACKUP_DIR` setting
2. **Directory Discovery**: Scans `BACKUP_DIR` for subdirectories containing Docker compose files:
   - `docker-compose.yml`
   - `docker-compose.yaml`
   - `compose.yml`
   - `compose.yaml`
3. **Current Status Loading**: Reads existing `.dirlist` file if it exists
4. **Automatic Synchronization** (if `--prune` or `--prune-only` is used):
   - Compares discovered directories with existing dirlist entries
   - Removes entries for directories that no longer exist
   - Adds entries for new directories (defaulted to `enabled=false` for safety)
   - Shows summary of changes made
   - Updates the `.dirlist` file automatically
5. **Interactive Selection** (unless `--prune-only` is used): Presents a checkbox dialog with all discovered directories
6. **Confirmation**: Shows summary of changes before saving
7. **File Update**: Updates the `.dirlist` file with new settings

### Synchronization Workflow

When using `--prune` or `--prune-only` options:

1. **Change Detection**: Analyzes differences between discovered directories and existing dirlist
2. **Removal Processing**: Identifies directories in dirlist that no longer exist in the backup directory
3. **Addition Processing**: Identifies new directories that exist but aren't in the dirlist
4. **Summary Display**: Shows what will be removed and added
5. **Automatic Update**: Applies changes and saves the updated dirlist
6. **Status Report**: Displays final summary of enabled/disabled directories

## Interface Screenshots

The script provides several dialog screens:

### Main Selection Dialog
```
┌─────────────────── Backup Directory Management ───────────────────┐
│ Select directories to include in backup:                           │
│                                                                     │
│ Use SPACE to toggle, ENTER to confirm, ESC to cancel              │
│                                                                     │
│    [ ] app1              Docker compose directory                  │
│    [X] app2              Docker compose directory                  │
│    [X] app3              Docker compose directory                  │
│    [ ] paperlessngx      Docker compose directory                  │
│                                                                     │
│                    <  OK  >        <Cancel>                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Confirmation Dialog
```
┌─────────────────────── Confirm Changes ───────────────────────────┐
│ Directory Backup Settings Summary:                                 │
│                                                                     │
│ ENABLED directories (will be backed up):                          │
│   ✓ app2                                                          │
│   ✓ app3                                                          │
│                                                                     │
│ DISABLED directories (will be skipped):                           │
│   ✗ app1                                                          │
│   ✗ paperlessngx                                                  │
│                                                                     │
│ Total: 2 enabled, 2 disabled                                      │
│                                                                     │
│ ⚠ Changes detected - .dirlist file will be updated               │
│                                                                     │
│ Do you want to save these settings?                               │
│                                                                     │
│                    < Yes >         < No >                         │
└─────────────────────────────────────────────────────────────────────┘
```

## File Format

The script manages the `.dirlist` file in the following format:

```bash
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup
app1=false
app2=true
app3=true
paperlessngx=false
```

## Error Handling

The script includes comprehensive error handling for:

- Missing `dialog` command
- Missing or invalid configuration file
- Non-existent backup directory
- File permission issues
- User cancellation

## Integration with Backup Script

The `manage-dirlist.sh` script is designed to work with the existing `docker-backup.sh` script:

- Uses the same configuration file format
- Follows the same directory discovery logic
- Maintains the same `.dirlist` file format
- Respects the same coding standards (bash strict mode, error handling)

## Testing

The script has been tested with the provided test environment:

```bash
# Run functionality tests
cd test-env
./simple-test.sh
./test-dirlist-functionality.sh

# Test the actual script (interactive)
BACKUP_CONFIG=./test-backup.conf ./manage-dirlist.sh
```

## Exit Codes

- `0`: Success
- `1`: Configuration error
- `2`: Dialog command not available
- `3`: User cancelled operation

## Security Considerations

- The script only reads the `BACKUP_DIR` setting from the configuration
- No sensitive information (passwords, repositories) is accessed
- File permissions are preserved when updating `.dirlist`
- The script validates all input and file operations

## Troubleshooting

### Dialog Not Found
```bash
# Install dialog package for your distribution
sudo apt-get install dialog  # Ubuntu/Debian
sudo yum install dialog      # CentOS/RHEL
sudo dnf install dialog      # Fedora
```

### Configuration Not Found
```bash
# Ensure backup.conf exists in the script directory
ls -la backup.conf

# Or specify custom location
BACKUP_CONFIG=/path/to/backup.conf ./manage-dirlist.sh
```

### No Directories Found
- Ensure `BACKUP_DIR` in configuration points to correct directory
- Verify subdirectories contain valid Docker compose files
- Check directory permissions

## Synchronization Examples

### Example 1: Adding New Directories

```bash
# Before: dirlist contains app1=true, app2=false
# Filesystem: app1/, app2/, app3/ (app3 is new)

$ ./manage-dirlist.sh --prune-only
[INFO] Performing automatic directory synchronization...
[SUCCESS] Added directories (defaulted to disabled):
  + app3 (enabled=false)
[INFO] Total changes: 0 removed, 1 added

# After: dirlist contains app1=true, app2=false, app3=false
```

### Example 2: Removing Deleted Directories

```bash
# Before: dirlist contains app1=true, app2=false, old-app=true
# Filesystem: app1/, app2/ (old-app was deleted)

$ ./manage-dirlist.sh --prune-only
[INFO] Performing automatic directory synchronization...
[WARNING] Removed directories (no longer exist):
  ✗ old-app
[INFO] Total changes: 1 removed, 0 added

# After: dirlist contains app1=true, app2=false
```

### Example 3: Mixed Changes

```bash
# Before: dirlist contains app1=true, old-app=false
# Filesystem: app1/, app2/, app3/ (old-app deleted, app2 and app3 added)

$ ./manage-dirlist.sh --prune-only
[INFO] Performing automatic directory synchronization...
[WARNING] Removed directories (no longer exist):
  ✗ old-app
[SUCCESS] Added directories (defaulted to disabled):
  + app2 (enabled=false)
  + app3 (enabled=false)
[INFO] Total changes: 1 removed, 2 added

# After: dirlist contains app1=true, app2=false, app3=false
```

### Example 4: No Changes Needed

```bash
$ ./manage-dirlist.sh --prune-only
[INFO] Performing automatic directory synchronization...
[SUCCESS] Directory list is already synchronized with backup directory
```

## Future Enhancements

Potential improvements for future versions:

- Bulk enable/disable options
- Directory filtering and search
- Import/export of directory lists
- Integration with backup scheduling
- Support for nested directory structures
- Scheduled automatic synchronization
- Backup of dirlist changes with timestamps