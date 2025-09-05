
#!/bin/bash

# Rclone Restore Script - OPTIMIZED VERSION
# Complete directory restore with metadata preservation and enhanced error handling
# Author: Generated for production use
# Version: 2.0 - Fixed hardcoded values and improved reliability

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${RCLONE_CONFIG:-$SCRIPT_DIR/rclone.conf}"

# Default configuration values
DEFAULT_TRANSFERS=4
DEFAULT_CHECKERS=8
DEFAULT_BUFFER_SIZE="16M"
DEFAULT_RETRIES=3
DEFAULT_RETRY_DELAY="1s"

# Configuration variables (externalized from hardcoded values)
REMOTE_NAME=""
BACKUP_PATH=""
RESTORE_DIR=""
LOG_DIR=""
RESTORE_LOG_FILE=""
TRANSFERS="$DEFAULT_TRANSFERS"
CHECKERS="$DEFAULT_CHECKERS"
BUFFER_SIZE="$DEFAULT_BUFFER_SIZE"
FAST_LIST="true"
PRESERVE_LINKS="true"
VERBOSE_OUTPUT="true"
PROGRESS_OUTPUT="true"
RETRIES="$DEFAULT_RETRIES"
RETRY_DELAY="$DEFAULT_RETRY_DELAY"
BANDWIDTH_LIMIT=""
EXCLUDE_PATTERNS=""

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_CONFIG_ERROR=1
readonly EXIT_VALIDATION_ERROR=2
readonly EXIT_RESTORE_ERROR=3

####
# Logging Functions
####

# Initialize logging
init_logging() {
    # Ensure log directory exists
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" || {
            echo "ERROR: Cannot create log directory: $LOG_DIR" >&2
            exit $EXIT_CONFIG_ERROR
        }
    fi
    
    # Ensure log file is writable
    if [[ ! -w "$RESTORE_LOG_FILE" ]] && [[ ! -w "$LOG_DIR" ]]; then
        echo "ERROR: Cannot write to log file: $RESTORE_LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Create log file if it doesn't exist
    touch "$RESTORE_LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot create log file: $RESTORE_LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Implement basic log rotation (keep last 50MB)
    if [[ -f "$RESTORE_LOG_FILE" ]] && [[ $(stat -f%z "$RESTORE_LOG_FILE" 2>/dev/null || stat -c%s "$RESTORE_LOG_FILE" 2>/dev/null || echo 0) -gt 52428800 ]]; then
        mv "$RESTORE_LOG_FILE" "${RESTORE_LOG_FILE}.old" 2>/dev/null || true
        touch "$RESTORE_LOG_FILE"
    fi
}

# Enhanced log message with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$RESTORE_LOG_FILE"
    
    # Also output to console with colors
    case "$level" in
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}" >&2
            ;;
        INFO)
            echo -e "${GREEN}[$timestamp] [INFO] $message${NC}"
            ;;
        DEBUG)
            echo -e "${BLUE}[$timestamp] [DEBUG] $message${NC}"
            ;;
        PROGRESS)
            echo -e "${CYAN}[$timestamp] [PROGRESS] $message${NC}"
            ;;
        *)
            echo "[$timestamp] [$level] $message"
            ;;
    esac
}

# Convenience logging functions
log_info() { log_message "INFO" "$@"; }
log_warn() { log_message "WARN" "$@"; }
log_error() { log_message "ERROR" "$@"; }
log_debug() { log_message "DEBUG" "$@"; }
log_progress() { log_message "PROGRESS" "$@"; }

####
# Configuration Management
####

# Load configuration from file
load_config() {
    log_info "Loading configuration from: $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return $EXIT_CONFIG_ERROR
    fi
    
    if [[ ! -r "$CONFIG_FILE" ]]; then
        log_error "Configuration file not readable: $CONFIG_FILE"
        return $EXIT_CONFIG_ERROR
    fi
    
    # Source the configuration file safely
    local config_content
    config_content="$(grep -E '^[A-Z_]+=.*' "$CONFIG_FILE" | grep -v '^#' || true)"
    
    if [[ -z "$config_content" ]]; then
        log_error "No valid configuration found in: $CONFIG_FILE"
        return $EXIT_CONFIG_ERROR
    fi
    
    # Parse configuration variables
    while IFS='=' read -r key value; do
        # Strip inline comments and whitespace from value
        value="$(echo "$value" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        
        case "$key" in
            REMOTE_NAME)
                REMOTE_NAME="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            BACKUP_PATH)
                BACKUP_PATH="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            RESTORE_DIR)
                RESTORE_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            LOG_DIR)
                LOG_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            RESTORE_LOG_FILE)
                RESTORE_LOG_FILE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            TRANSFERS)
                TRANSFERS="$value"
                ;;
            CHECKERS)
                CHECKERS="$value"
                ;;
            BUFFER_SIZE)
                BUFFER_SIZE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            FAST_LIST)
                FAST_LIST="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            PRESERVE_LINKS)
                PRESERVE_LINKS="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            VERBOSE_OUTPUT)
                VERBOSE_OUTPUT="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            PROGRESS_OUTPUT)
                PROGRESS_OUTPUT="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            RETRIES)
                RETRIES="$value"
                ;;
            RETRY_DELAY)
                RETRY_DELAY="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            BANDWIDTH_LIMIT)
                BANDWIDTH_LIMIT="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            EXCLUDE_PATTERNS)
                EXCLUDE_PATTERNS="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
        esac
    done <<< "$config_content"
    
    log_info "Configuration loaded successfully"
    return $EXIT_SUCCESS
}

# Validate configuration
validate_config() {
    log_info "Validating configuration"
    
    # Validate required fields
    if [[ -z "$REMOTE_NAME" ]]; then
        log_error "REMOTE_NAME not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    if [[ -z "$BACKUP_PATH" ]]; then
        log_error "BACKUP_PATH not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    if [[ -z "$RESTORE_DIR" ]]; then
        log_error "RESTORE_DIR not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    # Validate numeric parameters
    if ! [[ "$TRANSFERS" =~ ^[0-9]+$ ]] || [[ "$TRANSFERS" -lt 1 ]]; then
        log_warn "Invalid TRANSFERS value: $TRANSFERS, using default: $DEFAULT_TRANSFERS"
        TRANSFERS="$DEFAULT_TRANSFERS"
    fi
    
    if ! [[ "$CHECKERS" =~ ^[0-9]+$ ]] || [[ "$CHECKERS" -lt 1 ]]; then
        log_warn "Invalid CHECKERS value: $CHECKERS, using default: $DEFAULT_CHECKERS"
        CHECKERS="$DEFAULT_CHECKERS"
    fi
    
    if ! [[ "$RETRIES" =~ ^[0-9]+$ ]]; then
        log_warn "Invalid RETRIES value: $RETRIES, using default: $DEFAULT_RETRIES"
        RETRIES="$DEFAULT_RETRIES"
    fi
    
    # Validate boolean parameters
    for var_name in FAST_LIST PRESERVE_LINKS VERBOSE_OUTPUT PROGRESS_OUTPUT; do
        local var_value
        case "$var_name" in
            FAST_LIST) var_value="$FAST_LIST" ;;
            PRESERVE_LINKS) var_value="$PRESERVE_LINKS" ;;
            VERBOSE_OUTPUT) var_value="$VERBOSE_OUTPUT" ;;
            PROGRESS_OUTPUT) var_value="$PROGRESS_OUTPUT" ;;
        esac
        
        if [[ -n "$var_value" ]] && ! [[ "$var_value" =~ ^(true|false)$ ]]; then
            log_warn "Invalid $var_name value: $var_value, must be 'true' or 'false'. Using default: true"
            case "$var_name" in
                FAST_LIST) FAST_LIST="true" ;;
                PRESERVE_LINKS) PRESERVE_LINKS="true" ;;
                VERBOSE_OUTPUT) VERBOSE_OUTPUT="true" ;;
                PROGRESS_OUTPUT) PROGRESS_OUTPUT="true" ;;
            esac
        fi
    done
    
    log_info "Configuration validation completed"
    log_debug "REMOTE_NAME: $REMOTE_NAME"
    log_debug "BACKUP_PATH: $BACKUP_PATH"
    log_debug "RESTORE_DIR: $RESTORE_DIR"
    log_debug "LOG_DIR: $LOG_DIR"
    log_debug "TRANSFERS: $TRANSFERS"
    log_debug "CHECKERS: $CHECKERS"
    log_debug "BUFFER_SIZE: $BUFFER_SIZE"
    log_debug "RETRIES: $RETRIES"
    
    return $EXIT_SUCCESS
}

####
# Rclone Operations
####

# Check if rclone is available and remote is configured
check_rclone() {
    log_info "Checking rclone availability and remote configuration"
    
    if ! command -v rclone >/dev/null 2>&1; then
        log_error "rclone command not found. Please install rclone."
        return $EXIT_RESTORE_ERROR
    fi
    
    # Test remote access
    if ! rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        log_error "Cannot access rclone remote: $REMOTE_NAME"
        log_error "Please check your rclone configuration with: rclone config"
        return $EXIT_RESTORE_ERROR
    fi
    
    # Test if backup path exists on remote
    if ! rclone lsd "$REMOTE_NAME:$BACKUP_PATH" >/dev/null 2>&1; then
        log_error "Backup path does not exist on remote: $REMOTE_NAME:$BACKUP_PATH"
        log_error "Please check the backup path or run a backup first"
        return $EXIT_RESTORE_ERROR
    fi
    
    log_info "rclone is available and remote '$REMOTE_NAME' is accessible"
    log_info "Backup path '$BACKUP_PATH' exists on remote"
    return $EXIT_SUCCESS
}

# Prepare restore directory
prepare_restore_directory() {
    log_info "Preparing restore directory: $RESTORE_DIR"
    
    if [[ ! -d "$RESTORE_DIR" ]]; then
        log_info "Creating restore directory: $RESTORE_DIR"
        if ! mkdir -p "$RESTORE_DIR"; then
            log_error "Failed to create restore directory: $RESTORE_DIR"
            return $EXIT_RESTORE_ERROR
        fi
    fi
    
    if [[ ! -w "$RESTORE_DIR" ]]; then
        log_error "Restore directory not writable: $RESTORE_DIR"
        return $EXIT_RESTORE_ERROR
    fi
    
    log_info "Restore directory is ready: $RESTORE_DIR"
    return $EXIT_SUCCESS
}

# Build rclone command with all options
build_rclone_command() {
    local operation="$1"  # copy
    local source="$2"
    local destination="$3"
    
    local rclone_cmd=(rclone "$operation")
    
    # Add progress if enabled
    if [[ "$PROGRESS_OUTPUT" == "true" ]]; then
        rclone_cmd+=(--progress)
    fi
    
    # Add verbose if enabled
    if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
        rclone_cmd+=(--verbose)
    fi
    
    # Add links preservation if enabled
    if [[ "$PRESERVE_LINKS" == "true" ]]; then
        rclone_cmd+=(--links)
    fi
    
    # Add fast-list if enabled
    if [[ "$FAST_LIST" == "true" ]]; then
        rclone_cmd+=(--fast-list)
    fi
    
    # Add transfer settings
    rclone_cmd+=(--transfers "$TRANSFERS")
    rclone_cmd+=(--checkers "$CHECKERS")
    rclone_cmd+=(--buffer-size "$BUFFER_SIZE")
    
    # Add retry settings
    rclone_cmd+=(--retries "$RETRIES")
    rclone_cmd+=(--retries-sleep "$RETRY_DELAY")
    
    # Add bandwidth limit if specified
    if [[ -n "$BANDWIDTH_LIMIT" ]]; then
        rclone_cmd+=(--bwlimit "$BANDWIDTH_LIMIT")
        log_debug "Added bandwidth limit: $BANDWIDTH_LIMIT"
    fi
    
    # Add exclude patterns if specified
    if [[ -n "$EXCLUDE_PATTERNS" ]]; then
        IFS=',' read -ra EXCLUDES <<< "$EXCLUDE_PATTERNS"
        for exclude in "${EXCLUDES[@]}"; do
            rclone_cmd+=(--exclude "$exclude")
        done
        log_debug "Added exclude patterns: $EXCLUDE_PATTERNS"
    fi
    
    # Add log file
    rclone_cmd+=(--log-file "$RESTORE_LOG_FILE")
    
    # Add source and destination
    rclone_cmd+=("$source" "$destination")
    
    echo "${rclone_cmd[@]}"
}

# Perform the restore operation
perform_restore() {
    log_progress "Starting restore from $REMOTE_NAME:$BACKUP_PATH to $RESTORE_DIR"
    
    local restore_start_time
    restore_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Build rclone command
    local rclone_cmd
    rclone_cmd="$(build_rclone_command "copy" "$REMOTE_NAME:$BACKUP_PATH" "$RESTORE_DIR")"
    
    log_info "Executing rclone restore command"
    log_debug "Restore command: $rclone_cmd"
    
    # Execute rclone command
    if eval "$rclone_cmd"; then
        local restore_end_time
        restore_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
        log_info "Restore completed successfully"
        log_info "Restore start time: $restore_start_time"
        log_info "Restore end time: $restore_end_time"
        return $EXIT_SUCCESS
    else
        local exit_code=$?
        log_error "Restore FAILED! Exit code: $exit_code"
        log_error "Check $RESTORE_LOG_FILE for detailed error information"
        return $EXIT_RESTORE_ERROR
    fi
}

####
# Main Execution Flow
####

# Display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [CUSTOM_RESTORE_DIR]

Rclone Restore Script - OPTIMIZED VERSION

This script performs complete directory restore with metadata preservation
and enhanced error handling. All configuration is externalized to rclone.conf.

CRITICAL FIXES APPLIED:
- Fixed hardcoded remote name, backup path, and restore directory
- Added comprehensive configuration file support
- Enhanced error handling and logging
- Improved retry logic and bandwidth control
- Added exclude patterns and advanced rclone options

OPTIONS:
    -h, --help       Display this help message

ARGUMENTS:
    CUSTOM_RESTORE_DIR   Optional custom restore directory (overrides config)

CONFIGURATION:
    Configuration is read from: $CONFIG_FILE
    Required: REMOTE_NAME=your-rclone-remote-name
    Required: BACKUP_PATH=/path/on/remote
    Required: RESTORE_DIR=/path/to/restore/to
    Optional: LOG_DIR=/var/log/rclone (default)
    Optional: TRANSFERS=4, CHECKERS=8, BUFFER_SIZE=16M
    Optional: RETRIES=3, RETRY_DELAY=1s
    Optional: BANDWIDTH_LIMIT=10M (for bandwidth limiting)
    Optional: EXCLUDE_PATTERNS="*.tmp,*.log,cache/"

EXAMPLES:
    $SCRIPT_NAME                           # Restore to configured directory
    $SCRIPT_NAME /tmp/emergency-restore    # Restore to custom directory
    
PREREQUISITES:
    - rclone must be installed and configured
    - Remote must be set up with 'rclone config'
    - Backup path must exist on the remote

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Validation error
    3 - Restore error

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit $EXIT_SUCCESS
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit $EXIT_CONFIG_ERROR
                ;;
            *)
                # Custom restore directory
                RESTORE_DIR="$1"
                log_info "Using custom restore directory: $RESTORE_DIR"
                shift
                ;;
        esac
    done
}

# Main function
main() {
    local start_time
    start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Load and validate configuration first (before logging init)
    load_config || exit $?
    
    # Initialize logging after config is loaded
    init_logging
    
    log_info "=== Rclone Restore Started (OPTIMIZED) ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Start time: $start_time"
    
    validate_config || exit $?
    
    # Check prerequisites
    check_rclone || exit $?
    
    # Prepare restore directory
    prepare_restore_directory || exit $?
    
    # Perform restore
    perform_restore || exit $?
    
    local end_time
    end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    log_progress "=== Rclone Restore Completed Successfully ==="
    log_progress "Start time: $start_time"
    log_progress "End time: $end_time"
    log_progress "Source: $REMOTE_NAME:$BACKUP_PATH"
    log_progress "Destination: $RESTORE_DIR"
    
    exit $EXIT_SUCCESS
}

####
# Script Entry Point
####

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments first
    parse_arguments "$@"
    
    # Run main function
    main
fi
