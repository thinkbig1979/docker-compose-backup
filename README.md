# Docker Stack Selective Sequential Backup Script

A comprehensive bash script for selective, sequential backup of Docker compose stacks using restic. This script implements a two-phase approach: directory discovery with selective control, followed by sequential processing of enabled directories.

**Self-Contained Design**: This script is designed to be completely portable and self-contained within a single directory, with its configuration file located alongside the script.

## Features

- **Selective Directory Control**: Uses `.dirlist` file to enable/disable backup for each directory
- **Sequential Processing**: Processes directories one at a time for safer, more controlled backups
- **Two-Phase Operation**: Scan phase for discovery, backup phase for processing
- **Opt-In Approach**: New directories are disabled by default, requiring manual enablement
- **Smart Stack Management**: Intelligently tracks and manages Docker stack states (only stops/starts stacks that were originally running)
- **Initial State Tracking**: Records the initial state of all Docker stacks before any operations begin
- **Comprehensive Logging**: Detailed logging with timestamps, progress indicators, and severity levels including real-time restic output
- **Enhanced Error Handling**: Robust error handling with proper exit codes, recovery mechanisms, and individual directory failure isolation
- **Signal Handling**: Graceful shutdown on interruption signals with proper cleanup
- **Configuration Validation**: Validates all configuration parameters and prerequisites with fallback support
- **Dry Run Mode**: Test mode to verify operations without making changes
- **PID File Management**: Prevents concurrent script execution with stale PID detection
- **Restic Integration**: Uses restic for reliable, incremental backups with visible real-time output and comprehensive tagging
- **Flexible Configuration**: Supports both config file and environment variable configuration with automatic fallback

## How It Works

### Two-Phase Approach

**Phase 1: Directory Scanning**
1. Scans the target directory for subdirectories containing Docker compose files
2. Generates or updates the `.dirlist` file with directory enable/disable flags
3. New directories are added with `false` (disabled) by default
4. Removed directories are automatically cleaned from the list
5. Shows current status of all directories

**Phase 2: Sequential Processing**
1. Loads the `.dirlist` file to determine which directories to process
2. Records the initial state of all Docker stacks (running/stopped) before any operations
3. For each enabled directory (marked `true`):
   - Changes to the directory
   - **Smart Stop**: Only stops Docker stacks that were originally running
   - Uses restic to backup only that specific directory with comprehensive tagging
   - **Smart Start**: Only restarts Docker stacks that were originally running
   - Moves to the next enabled directory
4. Processes directories one at a time for maximum safety and control
5. Provides detailed progress reporting and error isolation per directory

### Directory List Management

The script automatically manages a `.dirlist` file in the script directory with the following format:

```
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup
directory1=false
directory2=true
directory3=false
```

**Key Behaviors:**
- **New directories**: Added as `false` (opt-in approach)
- **Deleted directories**: Automatically removed from list
- **Manual editing**: Users can edit the file to control which directories get backed up
- **Regeneration**: File is recreated if missing or corrupt

## Requirements

### System Requirements
- Linux/Unix system with bash 4.0+
- Docker and Docker Compose installed
- `restic` backup tool installed and configured
- `timeout` command (usually part of coreutils)

### Permissions
- Read access to the backup directory
- Write access to the script directory for logging, PID files, and `.dirlist`
- Docker permissions (usually requires user to be in `docker` group)
- Read access to the script directory for configuration file

### Restic Configuration
The script requires restic configuration to be specified in the `backup.conf` file:
- `RESTIC_REPOSITORY`: Path or URL to the restic repository
- `RESTIC_PASSWORD`: Password for the restic repository

**Fallback Support**: Environment variables `RESTIC_REPOSITORY` and `RESTIC_PASSWORD` are used as fallback if not specified in the config file (for backward compatibility). The script will automatically detect and use environment variables when config file values are empty.

## Installation

### Self-Contained Directory Setup (Recommended)

1. **Create a dedicated directory for the backup script:**
   ```bash
   mkdir -p ~/docker-backup
   cd ~/docker-backup
   ```

2. **Copy the script and configuration:**
   ```bash
   # Copy both files to the directory
   cp /path/to/docker-backup.sh .
   cp /path/to/backup.conf .
   chmod +x docker-backup.sh
   ```

3. **Edit the configuration file:**
   ```bash
   nano backup.conf
   # Configure BACKUP_DIR, RESTIC_REPOSITORY, and RESTIC_PASSWORD
   ```

4. **Configure restic repository (if not already done):**
   ```bash
   # Initialize repository (one-time setup)
   # Use the same values you configured in backup.conf
   export RESTIC_REPOSITORY="/path/to/backup/repo"
   export RESTIC_PASSWORD="your-secure-password"
   restic init
   ```

5. **Secure the configuration file:**
   ```bash
   # Protect the config file since it contains the restic password
   chmod 600 backup.conf
   ```

6. **The logs directory and .dirlist file are automatically created:**
   ```bash
   # The script automatically creates ./logs/ directory and .dirlist file when first run
   # No additional setup required
   ```

### Alternative: System-Wide Installation

If you prefer system-wide installation, you can still use the self-contained approach:

1. **Create system directory:**
   ```bash
   sudo mkdir -p /opt/docker-backup
   sudo cp docker-backup.sh backup.conf /opt/docker-backup/
   sudo chmod +x /opt/docker-backup/docker-backup.sh
   ```

2. **Create symbolic link (optional):**
   ```bash
   sudo ln -s /opt/docker-backup/docker-backup.sh /usr/local/bin/docker-backup
   ```

## Configuration

### Configuration File (`backup.conf`)

The script reads configuration from `backup.conf` in the same directory as the script. Modify the provided `backup.conf` file as needed:

```bash
# Required: Directory containing Docker compose stacks
BACKUP_DIR=/opt/docker-stacks

# Required: Restic repository configuration
RESTIC_REPOSITORY=/path/to/restic/repository
RESTIC_PASSWORD=your-secure-password

# Optional: Backup timeout in seconds (default: 3600)
# Increase for larger backup sets or slower storage
BACKUP_TIMEOUT=3600

# Optional: Docker command timeout in seconds (default: 30)
# Time to wait for docker compose stop/start commands
# Increase for complex stacks that take longer to stop/start
DOCKER_TIMEOUT=30
```

### Directory Structure

The script expects the following directory structure:

```
BACKUP_DIR/
├── stack1/
│   ├── docker-compose.yml
│   └── ... (other files)
├── stack2/
│   ├── docker-compose.yaml
│   └── ... (other files)
└── stack3/
    ├── compose.yml
    └── ... (other files)
```

Each subdirectory should contain a Docker compose file (supports `.yml` and `.yaml` extensions for both `docker-compose` and `compose` filenames).

## Usage

### Basic Usage

```bash
# Navigate to the script directory
cd ~/docker-backup

# Run selective backup (scan + process enabled directories)
./docker-backup.sh

# Run with verbose output to see detailed progress
./docker-backup.sh --verbose

# Perform a dry run (test without making changes)
./docker-backup.sh --dry-run

# Display help
./docker-backup.sh --help
```

**Note**: The script must be run from its own directory so it can find the `backup.conf` configuration file and manage the `.dirlist` file.

### Directory Selection

After the first run, edit the `.dirlist` file to control which directories are backed up:

```bash
# Edit the directory list
nano .dirlist

# Example content:
# webapp=true          # This directory will be backed up
# database=false       # This directory will be skipped
# monitoring=true      # This directory will be backed up
```

### Command Line Options

- `-v, --verbose`: Enable verbose output to console with detailed progress and debug information
- `-n, --dry-run`: Perform a dry run without making changes (shows what would be done)
- `-h, --help`: Display comprehensive help message with usage examples and exit codes

### Scheduling with Cron

To run automated backups, add to your crontab (or root's crontab if needed):

```bash
# Edit crontab
crontab -e

# Add entry for daily backup at 2 AM (change directory first)
0 2 * * * cd /home/user/docker-backup && ./docker-backup.sh >> ./logs/docker_backup_cron.log 2>&1

# Add entry for weekly backup with verbose logging
0 3 * * 0 cd /home/user/docker-backup && ./docker-backup.sh --verbose >> ./logs/docker_backup_weekly.log 2>&1
```

**Important**: Always include `cd` to change to the script directory before running, as the script needs to find its configuration file and manage the `.dirlist` file.

## Operation Flow

### Phase 1: Directory Scanning
1. **Initialization**
   - Load and validate configuration
   - Check restic availability and repository access
   - Create PID file to prevent concurrent runs
   - Set up signal handlers for graceful shutdown

2. **Directory Discovery**
   - Scan the backup directory for subdirectories
   - Identify directories containing Docker compose files
   - Update `.dirlist` file with discovered directories

3. **Directory List Management**
   - Add new directories as `false` (disabled by default)
   - Remove deleted directories from the list
   - Show current status of all directories

### Phase 2: Sequential Processing
1. **Load Directory List**
   - Read `.dirlist` file to determine enabled directories
   - Validate directory list format and count enabled directories

2. **Initial State Assessment**
   - Record the initial running state of all enabled Docker stacks
   - Categorize stacks as running, stopped, or not found
   - Display summary of initial states and planned actions

3. **Sequential Directory Processing**
   - For each directory marked `true` in `.dirlist`:
     - Change to the directory
     - **Smart Stop**: Only stop Docker stacks that were originally running
     - Backup the directory using restic with comprehensive tagging
     - **Smart Restart**: Only restart Docker stacks that were originally running
     - Continue to next enabled directory with individual error isolation

4. **Cleanup and Reporting**
   - Remove PID file
   - Log completion status and detailed timing
   - Report comprehensive success/failure statistics
   - Preserve first failure exit code for appropriate error reporting

## Directory Selection

### Manual Control

Edit the `.dirlist` file to control which directories are backed up:

```bash
# View current directory list
cat .dirlist

# Edit to enable/disable directories
nano .dirlist

# Example modifications:
# Change: webapp=false
# To:     webapp=true
```

### Opt-In Approach

- **New directories**: Automatically added as `false` (disabled)
- **User control**: Must manually edit `.dirlist` to enable backup
- **Safety first**: Prevents accidental backup of new directories

### Automatic Management

- **Directory removal**: Deleted directories are automatically removed from `.dirlist`
- **File regeneration**: `.dirlist` is recreated if missing or corrupt
- **Status reporting**: Shows current enable/disable status for all directories

## Smart Stack Management

### Intelligent State Tracking

The script implements sophisticated Docker stack state management that preserves the original state of your services:

**Initial State Assessment**:
- Before any backup operations begin, the script records the running state of all enabled Docker stacks
- Categorizes each stack as: `running`, `stopped`, or `not_found`
- Displays a comprehensive summary of initial states and planned actions

**Smart Stop Behavior**:
- **Running Stacks**: Only stops stacks that were originally running
- **Stopped Stacks**: Leaves already-stopped stacks untouched
- **Missing Stacks**: Gracefully handles directories that don't exist

**Smart Restart Behavior**:
- **Originally Running**: Restarts only stacks that were running before backup
- **Originally Stopped**: Leaves stacks stopped as they were originally
- **Backup Failures**: Attempts to restart originally running stacks even if backup failed

### State Preservation Examples

```bash
# Before backup:
# app1: RUNNING    → Will be stopped, backed up, then restarted
# app2: STOPPED    → Will remain stopped throughout the process
# app3: RUNNING    → Will be stopped, backed up, then restarted

# After backup:
# app1: RUNNING    → Restored to original state
# app2: STOPPED    → Preserved original state
# app3: RUNNING    → Restored to original state
```

### Benefits of Smart Management

- **Service Continuity**: Only disrupts services that were actually running
- **State Consistency**: Maintains your intended service configuration
- **Reduced Downtime**: Doesn't unnecessarily start stopped services
- **Error Recovery**: Attempts to restore original states even after failures
- **Operational Safety**: Prevents accidental service state changes

## Sequential Processing

### Benefits of Sequential Approach

- **Resource Management**: Processes one directory at a time, reducing system load
- **Error Isolation**: Failure in one directory doesn't affect others
- **Clear Progress**: Easy to track which directory is being processed
- **Safer Operations**: Reduces risk of Docker conflicts or resource contention
- **Smart State Management**: Preserves original stack states and only affects stacks that were actually running
- **Predictable Behavior**: Consistent processing order and timing

### Processing Steps for Each Directory

1. **Directory Validation**:
   - Verify directory exists and is accessible
   - Confirm presence of Docker compose files
   - Log directory path and current working directory

2. **Smart Stack Management**:
   - **Smart Stop**: Only stop stacks that were originally running (preserves stopped stacks)
   - Uses initial state tracking to determine appropriate action
   - Respects timeout settings for Docker operations
   - Logs all state decisions and actions taken

3. **Backup Operation**:
   - Restic backup with real-time visible output and progress
   - Comprehensive tagging including:
     - `docker-backup` (identifies backup source)
     - `selective-backup` (identifies backup method)
     - Directory name (for easy filtering)
     - Date stamp (for temporal organization)
   - Timeout protection with configurable duration
   - Real-time output streaming to console and log file

4. **Smart Stack Recovery**:
   - **Smart Restart**: Only restart stacks that were originally running
   - Automatic restart attempt even if backup fails (for originally running stacks)
   - Proper error handling and logging for restart operations
   - Maintains service availability for critical stacks

5. **Error Isolation**:
   - Individual directory failures don't stop processing of other directories
   - Detailed error logging with specific exit codes
   - Continuation of backup process for remaining directories
   - Preservation of first failure exit code for final script exit

6. **State Preservation**:
   - Returns to script directory after each operation
   - Maintains consistent working directory for subsequent operations
   - Preserves original Docker stack states regardless of backup success/failure

## Logging

### Log Levels
- **INFO**: Normal operation messages and status updates
- **PROGRESS**: Phase and directory processing progress with timestamps
- **WARN**: Warning conditions that don't stop execution (stale PID files, missing directories)
- **ERROR**: Error conditions that may affect operation (configuration, Docker, backup failures)
- **DEBUG**: Detailed debugging information (verbose mode only) including state tracking and command details
- **RESTIC**: Real-time restic command output with proper formatting and color coding

### Console Output

The script provides comprehensive console output showing:
- Current phase (scanning vs. processing) with clear phase separators
- Directory discovery results and count
- `.dirlist` file changes (additions, removals, status)
- Initial Docker stack states summary (running/stopped counts)
- Current directory being processed with progress indicators
- Each processing step: smart stopping, backing up, smart restarting
- Real-time restic output during backup operations with proper formatting
- Individual directory success/failure status
- Final comprehensive statistics including timing and failure counts
- Color-coded output for better readability (errors in red, warnings in yellow, etc.)

### Log Location
All operations are logged to `./logs/docker_backup.log` (in the script directory) with timestamps and severity levels.

### Log Rotation
Consider setting up log rotation to manage log file size:

```bash
# Create logrotate configuration (adjust path as needed)
sudo tee /etc/logrotate.d/docker-backup << EOF
/home/user/docker-backup/logs/docker_backup.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 user user
}
EOF
```

## Error Handling

### Exit Codes
- `0`: Success - all operations completed successfully
- `1`: Configuration error - missing or invalid configuration file, PID file issues
- `2`: Validation error - invalid backup directory, permission issues
- `3`: Backup error - restic command failures, backup timeout
- `4`: Docker error - Docker compose command failures, stack management issues
- `5`: Signal/interruption error - script interrupted by SIGINT, SIGTERM, or SIGHUP

### Error Recovery
- **Smart Recovery**: If backup fails for a directory, the script attempts to restart that directory's Docker stack (only if it was originally running)
- **Error Isolation**: Individual directory failures don't stop processing of other directories
- **State Preservation**: Original stack states are maintained regardless of backup success/failure
- **Comprehensive Logging**: Detailed error logging with exit codes helps with troubleshooting
- **Failure Tracking**: Final statistics report success/failure counts with first failure exit code preservation
- **Graceful Degradation**: Script continues processing remaining directories even after failures

### Common Issues and Solutions

1. **Permission Denied**
   ```bash
   # Ensure user has Docker permissions
   sudo usermod -aG docker $USER
   # Re-login or use newgrp docker
   ```

2. **Restic Repository Not Found**
   ```bash
   # Check configuration in backup.conf
   grep -E "RESTIC_" backup.conf
   
   # Check environment variables (fallback)
   echo $RESTIC_REPOSITORY
   echo $RESTIC_PASSWORD
   
   # Test restic access
   restic snapshots
   ```

3. **Docker Compose Not Found**
   ```bash
   # Install Docker Compose
   sudo apt-get install docker-compose-plugin
   # or
   sudo pip install docker-compose
   ```

4. **Timeout Issues**
   ```bash
   # Increase timeouts in backup.conf
   DOCKER_TIMEOUT=60
   BACKUP_TIMEOUT=7200
   ```

5. **Directory List Issues**
   ```bash
   # Regenerate .dirlist file by running the script
   ./docker-backup.sh --verbose
   
   # Manually edit .dirlist if needed
   nano .dirlist
   ```

## Security Considerations

- **Config File Security**: The `backup.conf` file contains the restic password in plain text
  - Set restrictive permissions: `chmod 600 backup.conf`
  - Ensure the file is owned by the backup user only
  - Consider using a dedicated backup user with limited privileges
- **Directory List Security**: The `.dirlist` file controls which directories are backed up
  - Protect from unauthorized modification
  - Review changes regularly
- **Password Management**: Consider using password files or secret management systems for production
- **File Permissions**: Restrict access to configuration files and log directories
- **Backup Validation**: Regularly test backup restoration procedures
- **Monitoring**: Monitor log files for security-related events and unauthorized access attempts

## Performance Considerations

### Sequential Processing Benefits
- **Predictable Resource Usage**: One directory at a time prevents resource spikes and system overload
- **Better Error Handling**: Easier to identify and handle individual directory issues with precise error isolation
- **Clearer Progress Tracking**: Users can see exactly which directory is being processed with detailed progress indicators
- **Reduced Docker Conflicts**: Avoids potential conflicts from parallel Docker operations and resource contention
- **Smart State Management**: Preserves original stack states and only affects stacks that were actually running
- **Safer Operations**: Minimizes risk of data corruption or service disruption during backup operations

### Timeouts
- **DOCKER_TIMEOUT**: Adjust based on stack complexity and shutdown/startup times (default: 30 seconds)
  - Increase for complex stacks with many containers or slow shutdown procedures
  - Monitor logs for timeout errors and adjust accordingly
- **BACKUP_TIMEOUT**: Adjust based on directory size and storage speed (default: 3600 seconds)
  - Increase for large backup sets or slower storage systems
  - Consider network speed for remote restic repositories
- **Timeout Monitoring**: Monitor logs to identify optimal values for your specific environment
- **Graceful Handling**: Timeout failures are properly logged and don't crash the entire backup process

### Restic Optimization
```bash
# Use restic with performance options
export RESTIC_CACHE_DIR=/tmp/restic-cache
export GOMAXPROCS=4  # Limit CPU usage

# For better performance with large repositories
export RESTIC_COMPRESSION=auto
export RESTIC_PACK_SIZE=16  # MB

# For network repositories, adjust connection settings
export RESTIC_CONNECTIONS=5
```

### Backup Tagging Strategy

The script uses a comprehensive tagging strategy for easy backup management:

```bash
# Automatic tags applied to each backup:
--tag "docker-backup"        # Identifies source as this script
--tag "selective-backup"     # Identifies backup method
--tag "$dir_name"           # Directory/stack name for filtering
--tag "$(date '+%Y-%m-%d')" # Date for temporal organization

# Example restic commands using tags:
restic snapshots --tag docker-backup                    # All backups from this script
restic snapshots --tag webapp                          # All backups of webapp directory
restic snapshots --tag docker-backup --tag 2024-01-15 # All backups from specific date
restic forget --tag webapp --keep-daily 7             # Retention policy for specific stack
```

## Monitoring and Alerting

### Health Checks
```bash
# Check last backup status
tail -n 50 ./logs/docker_backup.log | grep -E "(ERROR|WARN|Completed)"

# Check if backup is running
ps aux | grep docker-backup.sh

# View directory list status
cat .dirlist
```

### Integration with Monitoring Systems

The script's structured logging and exit codes make it easy to integrate with monitoring systems:

**Nagios/Icinga Integration**:
```bash
#!/bin/bash
# Nagios check script
cd /path/to/backup/script
./docker-backup.sh --dry-run >/dev/null 2>&1
exit_code=$?

case $exit_code in
    0) echo "OK - Backup script ready"; exit 0 ;;
    1) echo "CRITICAL - Configuration error"; exit 2 ;;
    2) echo "CRITICAL - Validation error"; exit 2 ;;
    *) echo "WARNING - Other error ($exit_code)"; exit 1 ;;
esac
```

**Prometheus Integration**:
```bash
# Export metrics after backup completion
echo "docker_backup_exit_code $exit_code" > /var/lib/node_exporter/docker_backup.prom
echo "docker_backup_directories_processed $processed_count" >> /var/lib/node_exporter/docker_backup.prom
echo "docker_backup_directories_failed $failed_count" >> /var/lib/node_exporter/docker_backup.prom
echo "docker_backup_last_run $(date +%s)" >> /var/lib/node_exporter/docker_backup.prom
```

**Custom Monitoring Script**:
```bash
#!/bin/bash
# Monitor backup health
LOG_FILE="/path/to/backup/script/logs/docker_backup.log"

# Check for recent successful completion
if tail -n 50 "$LOG_FILE" | grep -q "Backup Completed.*failed: 0"; then
    echo "Backup healthy"
    exit 0
else
    echo "Backup issues detected"
    exit 1
fi
```

## Troubleshooting

### Debug Mode
Run with verbose flag to see detailed operation logs:
```bash
cd /path/to/script/directory
./docker-backup.sh --verbose
```

### Manual Testing
Test individual components:
```bash
# Test configuration loading
cd /path/to/script/directory
bash -c 'source ./backup.conf && echo $BACKUP_DIR && echo $RESTIC_REPOSITORY'

# Test restic access (after loading config)
cd /path/to/script/directory
source ./backup.conf
export RESTIC_REPOSITORY RESTIC_PASSWORD
restic snapshots

# Test Docker compose in a directory
cd /path/to/stack && docker compose stop && docker compose start --detach

# Check directory list
cat .dirlist
```

### Log Analysis
```bash
# View recent errors with context
grep ERROR ./logs/docker_backup.log | tail -10

# View backup timing and duration
grep -E "(Started|Completed)" ./logs/docker_backup.log | tail -10

# View directory processing status
grep -E "(Processing|Successfully)" ./logs/docker_backup.log | tail -20

# View directory list changes
grep -E "(Added|Removed|Updated)" ./logs/docker_backup.log | tail -10

# View Docker stack state changes
grep -E "(initially|Smart|Skipping)" ./logs/docker_backup.log | tail -15

# View restic backup output
grep "RESTIC" ./logs/docker_backup.log | tail -20

# Monitor real-time backup progress
tail -f ./logs/docker_backup.log | grep -E "(PROGRESS|ERROR|RESTIC)"
```

## Migration from Previous Version

If upgrading from the parallel processing version:

1. **Backup your current configuration:**
   ```bash
   cp backup.conf backup.conf.old
   ```

2. **Update configuration file:**
   - Remove `PARALLEL_JOBS` parameter (no longer used)
   - Review and update other settings as needed

3. **First run will create .dirlist:**
   ```bash
   ./docker-backup.sh --verbose --dry-run
   ```

4. **Enable desired directories:**
   ```bash
   nano .dirlist
   # Change directories from false to true as needed
   ```

5. **Test with dry run:**
   ```bash
   ./docker-backup.sh --verbose --dry-run
   ```

## Test Environment

The script includes a comprehensive test environment in the `test-env/` directory for development and validation:

### Test Environment Structure
```
test-env/
├── docker-stacks/          # Mock Docker stack directories
│   ├── app1/              # Test application 1
│   ├── app2/              # Test application 2
│   └── app3/              # Test application 3
├── test-backup.conf       # Test configuration file
├── test-dirlist           # Test directory list
├── mock-commands.sh       # Mock Docker and restic commands
└── various test runners   # Multiple test suite implementations
```

### Running Tests
```bash
# Navigate to test environment
cd test-env/

# Run comprehensive test suite
./comprehensive-test-runner.sh

# Run specific test scenarios
./working-test-runner.sh

# Debug individual components
./debug-test-runner.sh
```

### Test Features
- **Mock Commands**: Simulates Docker and restic commands without actual execution
- **State Tracking**: Tests smart stack management and state preservation
- **Error Scenarios**: Tests error handling and recovery mechanisms
- **Configuration Testing**: Validates configuration loading and validation
- **Directory Management**: Tests `.dirlist` file management and updates
- **Signal Handling**: Tests graceful shutdown and cleanup procedures
- **PID Management**: Tests concurrent execution prevention
- **Timeout Handling**: Tests timeout scenarios for Docker and backup operations

### Test Environment Configuration

The test environment uses a separate configuration file (`test-backup.conf`) and directory structure:

```bash
# Test configuration
BACKUP_DIR=./docker-stacks
BACKUP_TIMEOUT=60
DOCKER_TIMEOUT=10
RESTIC_REPOSITORY=./backup-repo
RESTIC_PASSWORD=test-password
```

### Mock Command Behavior

The test environment includes sophisticated mock commands that simulate real behavior:

```bash
# Mock docker compose commands
docker compose stop    # Simulates stack shutdown with configurable delay
docker compose start   # Simulates stack startup with configurable delay
docker compose ps      # Returns mock container status

# Mock restic commands
restic backup          # Simulates backup operation with progress output
restic snapshots       # Returns mock snapshot list
restic init           # Simulates repository initialization
```

## Advanced Usage Patterns

### Selective Backup Strategies

**Development Environment**:
```bash
# Enable only development stacks
echo "webapp-dev=true
database-dev=true
redis-dev=false" > .dirlist
```

**Production Environment**:
```bash
# Enable critical production services
echo "webapp-prod=true
database-prod=true
monitoring=true
logging=false" > .dirlist
```

**Maintenance Mode**:
```bash
# Temporarily disable all backups
sed -i 's/=true/=false/g' .dirlist
# Re-enable after maintenance
sed -i 's/=false/=true/g' .dirlist
```

### Backup Scheduling Patterns

**Staggered Backups**:
```bash
# Different schedules for different priorities
# Critical services - daily at 2 AM
0 2 * * * cd /opt/backup && echo "critical-app=true" > .dirlist && ./docker-backup.sh

# Development services - weekly
0 3 * * 0 cd /opt/backup && echo "dev-app=true" > .dirlist && ./docker-backup.sh
```

**Resource-Aware Scheduling**:
```bash
# Low-resource hours for large backups
0 1 * * * cd /opt/backup && BACKUP_TIMEOUT=7200 ./docker-backup.sh
```

### Integration Patterns

**CI/CD Pipeline Integration**:
```bash
#!/bin/bash
# Pre-deployment backup
cd /opt/backup-script
echo "production-app=true" > .dirlist
./docker-backup.sh --verbose
if [ $? -eq 0 ]; then
    echo "Backup successful, proceeding with deployment"
else
    echo "Backup failed, aborting deployment"
    exit 1
fi
```

**Health Check Integration**:
```bash
#!/bin/bash
# Health check script
SCRIPT_DIR="/opt/backup-script"
LOG_FILE="$SCRIPT_DIR/logs/docker_backup.log"

# Check if backup completed successfully in last 24 hours
if find "$LOG_FILE" -mtime -1 -exec grep -q "failed: 0" {} \; 2>/dev/null; then
    echo "Backup system healthy"
    exit 0
else
    echo "Backup system requires attention"
    exit 1
fi
```

### Best Practices

**Security Hardening**:
```bash
# Secure the backup directory
chmod 700 /opt/backup-script
chmod 600 /opt/backup-script/backup.conf
chown backup-user:backup-group /opt/backup-script

# Use dedicated backup user
sudo useradd -r -s /bin/bash backup-user
sudo usermod -aG docker backup-user
```

**Performance Optimization**:
```bash
# For large environments, consider:
# 1. Separate backup schedules by priority
# 2. Use faster storage for restic cache
# 3. Optimize restic repository settings
export RESTIC_CACHE_DIR=/fast-storage/restic-cache
export RESTIC_COMPRESSION=auto
```

**Monitoring Integration**:
```bash
# Send notifications on failure
if ! ./docker-backup.sh; then
    echo "Backup failed" | mail -s "Backup Alert" admin@company.com
fi

# Log to syslog for centralized monitoring
logger -t docker-backup "Backup completed with exit code: $?"
```

## Contributing

When modifying the script:
1. **Code Quality**: Follow bash best practices (shellcheck compliance)
2. **Error Handling**: Maintain comprehensive error handling with proper exit codes
3. **Logging**: Update logging for new operations with appropriate log levels
4. **Testing**: Test with various Docker compose configurations and use the test environment
5. **Documentation**: Update documentation for any new features or changes
6. **Sequential Processing**: Ensure sequential processing approach is maintained
7. **State Management**: Preserve smart stack management and initial state tracking
8. **Backward Compatibility**: Maintain configuration file and environment variable fallback support

## License

This script is provided as-is for production use. Modify and distribute according to your organization's policies.