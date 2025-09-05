
#!/bin/bash

# Rclone Backup Script - OPTIMIZED VERSION
# Complete directory backup with metadata preservation and enhanced error handling
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
SOURCE_DIR=""
REMOTE_NAME=""
BACKUP_PATH=""
LOG_DIR=""
BACKUP_LOG_FILE=""
TRANSFERS="$DEFAULT_TRANSFERS"
CHECKERS="$DEFAULT_CHECKERS"
BUFFER_SIZE="$DEFAULT_BUFFER_SIZE"
FAST_LIST="true"
UPDATE_ONLY="true"
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
readonly EXIT_BACKUP_ERROR=3

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
    if [[ ! -w "$BACKUP_LOG_FILE" ]] && [[ ! -w "$LOG_DIR" ]]; then
        echo "ERROR: Cannot write to log file: $BACKUP_LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Create log file if it doesn't exist
    touch "$BACKUP_LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot create log file: $BACKUP_LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    }
    
    # Implement basic log rotation (keep last 50MB)
    if [[ -f "$BACKUP_LOG_FILE" ]] && [[ $(stat -f%z "$BACKUP_LOG_FILE" 2>/dev/null || stat -c%s "$BACKUP_LOG_FILE" 2>/dev/null || echo 0) -gt 52428800 ]]; then
        mv "$BACKUP_LOG_FILE" "${BACKUP_LOG_FILE}.old" 2>/dev/null || true
        touch "$BACKUP_LOG_FILE"
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
    echo "[$timestamp] [$level] $message" >> "$BACKUP_LOG_FILE"
    
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
            SOURCE_DIR)
                SOURCE_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            REMOTE_NAME)
                REMOTE_NAME="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            BACKUP_PATH)
                BACKUP_PATH="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            LOG_DIR)
                LOG_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            BACKUP_LOG_FILE)
                BACKUP_LOG_FILE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
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
            UPDATE_ONLY)
                UPDATE_ONLY="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
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
    if [[ -z "$SOURCE_DIR" ]]; then
        log_error "SOURCE_DIR not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    if [[ -z "$REMOTE_NAME" ]]; then
        log_error "REMOTE_NAME not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    if [[ -z "$BACKUP_PATH" ]]; then
        log_error "BACKUP_PATH not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    # Validate source directory
    if [[ ! -d "$SOURCE_DIR" ]]; then
        log_error "Source directory does not exist: $SOURCE_DIR"
        return $EXIT_VALIDATION_ERROR
    fi
    
    if [[ ! -r "$SOURCE_DIR" ]]; then
        log_error "Source directory not readable: $SOURCE_DIR"
        return $EXIT_VALIDATION_ERROR
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
    for var_name in FAST_LIST UPDATE_ONLY PRESERVE_LINKS VERBOSE_OUTPUT PROGRESS_OUTPUT; do
        local var_value
        case "$var_name" in
            FAST_LIST) var_value="$FAST_LIST" ;;
            UPDATE_ONLY) var_value="$UPDATE_ONLY" ;;
            PRESERVE_LINKS) var_value="$PRESERVE_LINKS" ;;
            VERBOSE_OUTPUT) var_value="$VERBOSE_OUTPUT" ;;
            PROGRESS_OUTPUT) var_value="$PROGRESS_OUTPUT" ;;
        esac
        
        if [[ -n "$var_value" ]] && ! [[ "$var_value" =~ ^(true|false)$ ]]; then
            log_warn "Invalid $var_name value: $var_value, must be 'true' or 'false'. Using default: true"
            case "$var_name" in
                FAST_LIST) FAST_LIST="true" ;;
                UPDATE_ONLY) UPDATE_ONLY="true" ;;
                PRESERVE_LINKS) PRESERVE_LINKS="true" ;;
                VERBOSE_OUTPUT) VERBOSE_OUTPUT="true" ;;
                PROGRESS_OUTPUT) PROGRESS_OUTPUT="true" ;;
            esac
        fi
    done
    
    log_info "Configuration validation completed"
    log_debug "SOURCE_DIR: $SOURCE_DIR"
    log_debug "REMOTE_NAME: $REMOTE_NAME"
    log_debug "BACKUP_PATH: $BACKUP_PATH"
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
        return $EXIT_BACKUP_ERROR
    fi
    
    # Test remote access
    if ! rclone lsd "$REMOTE_NAME:" >/dev/null 2>&1; then
        log_error "Cannot access rclone remote: $REMOTE_NAME"
        log_error "Please check your rclone configuration with: rclone config"
        return $EXIT_BACKUP_ERROR
    fi
    
    log_info "rclone is available and remote '$REMOTE_NAME' is accessible"
    return $EXIT_SUCCESS
}

# Build rclone command with all options
build_rclone_command() {
    local operation="$1"  # sync or copy
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
    
    # Add update only if enabled
    if [[ "$UPDATE_ONLY" == "true" ]]; then
        rclone_cmd+=(--update)
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
    rclone_cmd+=(--log-file "$BACKUP_LOG_FILE")
    
    # Add source and destination
    rclone_cmd+=("$source" "$destination")
    
    echo "${rclone_cmd[@]}"
}

# Perform the backup operation
perform_backup() {
    log_progress "Starting backup of $SOURCE_DIR to $REMOTE_NAME:$BACKUP_PATH"
    
    local backup_start_time
    backup_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Build rclone command
    local rclone_cmd
    rclone_cmd="$(build_rclone_command "sync" "$SOURCE_DIR" "$REMOTE_NAME:$BACKUP_PATH")"
    
    log_info "Executing rclone backup command"
    log_debug "Backup command: $rclone_cmd"
    
    # Execute rclone command
    if eval "$rclone_cmd"; then
        local backup_end_time
        backup_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
        log_info "Backup completed successfully"
        log_info "Backup start time: $backup_start_time"
        log_info "Backup end time: $backup_end_time"
        return $EXIT_SUCCESS
    else
        local exit_code=$?
        log_error "Backup FAILED! Exit code: $exit_code"
        log_error "Check $BACKUP_LOG_FILE for detailed error information"
        return $EXIT_BACKUP_ERROR
    fi
}

####
# Main Execution Flow
####

# Display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Rclone Backup Script - OPTIMIZED VERSION

This script performs complete directory backup with metadata preservation
and enhanced error handling. All configuration is externalized to rclone.conf.

CRITICAL FIXES APPLIED:
- Fixed hardcoded source directory, remote name, and paths
- Added comprehensive configuration file support
- Enhanced error handling and logging
- Improved retry logic and bandwidth control
- Added exclude patterns and advanced rclone options

OPTIONS:
    -h, --help       Display this help message

CONFIGURATION:
    Configuration is read from: $CONFIG_FILE
    Required: SOURCE_DIR=/path/to/source/directory
    Required: REMOTE_NAME=your-rclone-remote-name
    Required: BACKUP_PATH=/path/on/remote
    Optional: LOG_DIR=/var/log/rclone (default)
    Optional: TRANSFERS=4, CHECKERS=8, BUFFER_SIZE=16M
    Optional: RETRIES=3, RETRY_DELAY=1s
    Optional: BANDWIDTH_LIMIT=10M (for bandwidth limiting)
    Optional: EXCLUDE_PATTERNS="*.tmp,*.log,cache/"

EXAMPLES:
    $SCRIPT_NAME                # Run backup with config file settings
    
PREREQUISITES:
    - rclone must be installed and configured
    - Remote must be set up with 'rclone config'
    - Source directory must exist and be readable

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Validation error
    3 - Backup error

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
            *)
                log_error "Unknown option: $1"
                usage
                exit $EXIT_CONFIG_ERROR
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
    
    log_info "=== Rclone Backup Started (OPTIMIZED) ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Start time: $start_time"
    
    validate_config || exit $?
    
    # Check prerequisites
    check_rclone || exit $?
    
    # Perform backup
    perform_backup || exit $?
    
    local end_time
    end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    log_progress "=== Rclone Backup Completed Successfully ==="
    log_progress "Start time: $start_time"
    log_progress "End time: $end_time"
    log_progress "Source: $SOURCE_DIR"
    log_progress "Destination: $REMOTE_NAME:$BACKUP_PATH"
    
    exit $EXIT_SUCCESS
}

####
# Script Entry Point
####

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for help option first
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            usage
            exit $EXIT_SUCCESS
        fi
    done
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main function
    main
fi
