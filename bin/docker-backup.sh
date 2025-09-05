#!/bin/bash

# Docker Stack Selective Sequential Backup Script
# Selective backup solution for Docker compose stacks using restic
# Author: Generated for production use
# Version: 2.0 - Redesigned for selective, sequential processing

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/../config/backup.conf}"
readonly LOG_FILE="$SCRIPT_DIR/../logs/docker_backup.log"
readonly PID_FILE="$SCRIPT_DIR/../logs/docker_backup.pid"
readonly DIRLIST_FILE="$SCRIPT_DIR/../dirlist"

# Default configuration
DEFAULT_BACKUP_TIMEOUT=3600
DEFAULT_DOCKER_TIMEOUT=30

# Phase 1 Feature Flags - Security & Verification
ENABLE_PASSWORD_FILE=false
ENABLE_PASSWORD_COMMAND=false
ENABLE_BACKUP_VERIFICATION=false
VERIFICATION_DEPTH="files"
MIN_DISK_SPACE_MB=1024

# Phase 2 Feature Flags - Resource Monitoring & Performance
ENABLE_PERFORMANCE_MODE=false
ENABLE_DOCKER_STATE_CACHE=false
ENABLE_PARALLEL_PROCESSING=false
MAX_PARALLEL_JOBS=2
MEMORY_THRESHOLD_MB=512
LOAD_THRESHOLD=80
CHECK_SYSTEM_RESOURCES=false

# Phase 3 Feature Flags - Enhanced Monitoring & UX
ENABLE_JSON_LOGGING=false
ENABLE_PROGRESS_BARS=false
ENABLE_METRICS_COLLECTION=false
JSON_LOG_FILE=""

# Global variables
BACKUP_DIR=""
BACKUP_TIMEOUT="${DEFAULT_BACKUP_TIMEOUT}"
DOCKER_TIMEOUT="${DEFAULT_DOCKER_TIMEOUT}"
RESTIC_REPOSITORY=""
RESTIC_PASSWORD=""
RESTIC_PASSWORD_FILE=""
RESTIC_PASSWORD_COMMAND=""
HOSTNAME=""
KEEP_DAILY=""
KEEP_WEEKLY=""
KEEP_MONTHLY=""
KEEP_YEARLY=""
AUTO_PRUNE=""
# Phase 1 variables
PASSWORD_FILE=""
PASSWORD_COMMAND=""
# Phase 2 variables
DOCKER_STATE_CACHE_FILE=""
PARALLEL_JOBS=1
# Phase 3 variables
METRICS_FILE=""
BACKUP_START_TIMESTAMP=""
VERBOSE=false
DRY_RUN=false

# Global associative arrays
declare -A DIRLIST_ARRAY
declare -A STACK_INITIAL_STATE

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
readonly EXIT_DOCKER_ERROR=4
readonly EXIT_SIGNAL_ERROR=5

#######################################
# Logging Functions
#######################################

# Initialize logging
init_logging() {
    # Ensure log directory exists
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "ERROR: Cannot create log directory: $log_dir" >&2
            exit $EXIT_CONFIG_ERROR
        }
    fi
    
    # Also ensure the logs directory exists relative to script directory
    mkdir -p "$SCRIPT_DIR/logs" || {
        echo "ERROR: Cannot create script logs directory: $SCRIPT_DIR/logs" >&2
        exit $EXIT_CONFIG_ERROR
    }
    
    # Ensure log file is writable
    if [[ ! -w "$LOG_FILE" ]] && [[ ! -w "$log_dir" ]]; then
        echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot create log file: $LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    }
}

# Log message with timestamp and severity
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Also output to console if verbose, error/warning, progress, or restic output
    if [[ "$VERBOSE" == true ]] || [[ "$level" =~ ^(ERROR|WARN|PROGRESS|RESTIC)$ ]]; then
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
            RESTIC)
                echo -e "${CYAN}$message${NC}"
                ;;
            *)
                echo "[$timestamp] [$level] $message"
                ;;
        esac
    fi
}

# Convenience logging functions
log_info() { log_message "INFO" "$@"; }
log_warn() { log_message "WARN" "$@"; }
log_error() { log_message "ERROR" "$@"; }
log_debug() { log_message "DEBUG" "$@"; }
log_progress() { log_message "PROGRESS" "$@"; }

#######################################
# Signal Handling
#######################################

# Cleanup function for graceful shutdown
cleanup() {
    local exit_code=$?
    log_info "Cleanup initiated (exit code: $exit_code)"
    
    # Remove PID file
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE" 2>/dev/null || true
    fi
    
    # Clean up Phase 2 temporary files
    if [[ -n "$DOCKER_STATE_CACHE_FILE" && -f "$DOCKER_STATE_CACHE_FILE" ]]; then
        rm -f "$DOCKER_STATE_CACHE_FILE" 2>/dev/null || true
        log_debug "Cleaned up Docker state cache file"
    fi
    
    # If we were interrupted during backup, log it
    if [[ $exit_code -eq $EXIT_SIGNAL_ERROR ]]; then
        log_warn "Script interrupted by signal"
    fi
    
    log_info "Cleanup completed"
    exit $exit_code
}

# Signal handlers
handle_signal() {
    local signal="$1"
    log_warn "Received signal: $signal"
    exit $EXIT_SIGNAL_ERROR
}

# Set up signal traps
setup_signal_handlers() {
    trap cleanup EXIT
    trap 'handle_signal SIGINT' SIGINT
    trap 'handle_signal SIGTERM' SIGTERM
    trap 'handle_signal SIGHUP' SIGHUP
}

#######################################
# Configuration Management
#######################################

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
        # Remove everything from first # character onwards, then trim whitespace
        value="$(echo "$value" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        
        case "$key" in
            BACKUP_DIR)
                BACKUP_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            BACKUP_TIMEOUT)
                BACKUP_TIMEOUT="$value"
                ;;
            DOCKER_TIMEOUT)
                DOCKER_TIMEOUT="$value"
                ;;
            RESTIC_REPOSITORY)
                RESTIC_REPOSITORY="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            RESTIC_PASSWORD)
                RESTIC_PASSWORD="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            RESTIC_PASSWORD_FILE)
                RESTIC_PASSWORD_FILE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                PASSWORD_FILE="$RESTIC_PASSWORD_FILE"
                ;;
            RESTIC_PASSWORD_COMMAND)
                RESTIC_PASSWORD_COMMAND="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                PASSWORD_COMMAND="$RESTIC_PASSWORD_COMMAND"
                ;;
            ENABLE_PASSWORD_FILE)
                ENABLE_PASSWORD_FILE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_PASSWORD_COMMAND)
                ENABLE_PASSWORD_COMMAND="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_BACKUP_VERIFICATION)
                ENABLE_BACKUP_VERIFICATION="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            VERIFICATION_DEPTH)
                VERIFICATION_DEPTH="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            MIN_DISK_SPACE_MB)
                MIN_DISK_SPACE_MB="$value"
                ;;
            ENABLE_PERFORMANCE_MODE)
                ENABLE_PERFORMANCE_MODE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_DOCKER_STATE_CACHE)
                ENABLE_DOCKER_STATE_CACHE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_PARALLEL_PROCESSING)
                ENABLE_PARALLEL_PROCESSING="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            MAX_PARALLEL_JOBS)
                MAX_PARALLEL_JOBS="$value"
                ;;
            MEMORY_THRESHOLD_MB)
                MEMORY_THRESHOLD_MB="$value"
                ;;
            LOAD_THRESHOLD)
                LOAD_THRESHOLD="$value"
                ;;
            CHECK_SYSTEM_RESOURCES)
                CHECK_SYSTEM_RESOURCES="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_JSON_LOGGING)
                ENABLE_JSON_LOGGING="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_PROGRESS_BARS)
                ENABLE_PROGRESS_BARS="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            ENABLE_METRICS_COLLECTION)
                ENABLE_METRICS_COLLECTION="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            JSON_LOG_FILE)
                JSON_LOG_FILE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            HOSTNAME)
                HOSTNAME="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            KEEP_DAILY)
                KEEP_DAILY="$value"
                ;;
            KEEP_WEEKLY)
                KEEP_WEEKLY="$value"
                ;;
            KEEP_MONTHLY)
                KEEP_MONTHLY="$value"
                ;;
            KEEP_YEARLY)
                KEEP_YEARLY="$value"
                ;;
            AUTO_PRUNE)
                AUTO_PRUNE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
        esac
    done <<< "$config_content"
    
    log_info "Configuration loaded successfully"
    return $EXIT_SUCCESS
}

# Validate configuration
validate_config() {
    log_info "Validating configuration"
    
    # Validate BACKUP_DIR
    if [[ -z "$BACKUP_DIR" ]]; then
        log_error "BACKUP_DIR not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory does not exist: $BACKUP_DIR"
        return $EXIT_VALIDATION_ERROR
    fi
    
    if [[ ! -r "$BACKUP_DIR" ]]; then
        log_error "Backup directory not readable: $BACKUP_DIR"
        return $EXIT_VALIDATION_ERROR
    fi
    
    # Validate numeric parameters
    if ! [[ "$BACKUP_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$BACKUP_TIMEOUT" -lt 60 ]]; then
        log_warn "Invalid BACKUP_TIMEOUT value: $BACKUP_TIMEOUT, using default: $DEFAULT_BACKUP_TIMEOUT"
        BACKUP_TIMEOUT="$DEFAULT_BACKUP_TIMEOUT"
    fi
    
    if ! [[ "$DOCKER_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$DOCKER_TIMEOUT" -lt 5 ]]; then
        log_warn "Invalid DOCKER_TIMEOUT value: $DOCKER_TIMEOUT, using default: $DEFAULT_DOCKER_TIMEOUT"
        DOCKER_TIMEOUT="$DEFAULT_DOCKER_TIMEOUT"
    fi
    
    # Validate restic configuration
    if [[ -z "$RESTIC_REPOSITORY" ]]; then
        log_error "RESTIC_REPOSITORY not specified in configuration"
        return $EXIT_CONFIG_ERROR
    fi
    
    # Enhanced password validation - now supports multiple methods
    local password_methods=0
    if [[ -n "$RESTIC_PASSWORD" ]]; then
        password_methods=$((password_methods + 1))
    fi
    if [[ "$ENABLE_PASSWORD_FILE" == "true" && -n "$PASSWORD_FILE" ]]; then
        password_methods=$((password_methods + 1))
    fi
    if [[ "$ENABLE_PASSWORD_COMMAND" == "true" && -n "$PASSWORD_COMMAND" ]]; then
        password_methods=$((password_methods + 1))
    fi
    
    if [[ $password_methods -eq 0 ]]; then
        log_error "No password method configured. Set RESTIC_PASSWORD, or enable password file/command"
        return $EXIT_CONFIG_ERROR
    elif [[ $password_methods -gt 1 ]]; then
        log_warn "Multiple password methods configured. Priority: password file > password command > direct password"
    fi
    
    # Validate retention policy numeric parameters
    for var_name in KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY KEEP_YEARLY; do
        local var_value
        case "$var_name" in
            KEEP_DAILY) var_value="$KEEP_DAILY" ;;
            KEEP_WEEKLY) var_value="$KEEP_WEEKLY" ;;
            KEEP_MONTHLY) var_value="$KEEP_MONTHLY" ;;
            KEEP_YEARLY) var_value="$KEEP_YEARLY" ;;
        esac
        
        if [[ -n "$var_value" ]] && ! [[ "$var_value" =~ ^[0-9]+$ ]]; then
            log_warn "Invalid $var_name value: $var_value, must be a positive integer. Ignoring this setting."
            case "$var_name" in
                KEEP_DAILY) KEEP_DAILY="" ;;
                KEEP_WEEKLY) KEEP_WEEKLY="" ;;
                KEEP_MONTHLY) KEEP_MONTHLY="" ;;
                KEEP_YEARLY) KEEP_YEARLY="" ;;
            esac
        fi
    done
    
    # Validate AUTO_PRUNE boolean
    if [[ -n "$AUTO_PRUNE" ]] && ! [[ "$AUTO_PRUNE" =~ ^(true|false)$ ]]; then
        log_warn "Invalid AUTO_PRUNE value: $AUTO_PRUNE, must be 'true' or 'false'. Using default: false"
        AUTO_PRUNE="false"
    fi
    
    # Validate Phase 1, 2 & 3 feature flags
    for flag in ENABLE_PASSWORD_FILE ENABLE_PASSWORD_COMMAND ENABLE_BACKUP_VERIFICATION ENABLE_PERFORMANCE_MODE ENABLE_DOCKER_STATE_CACHE ENABLE_PARALLEL_PROCESSING CHECK_SYSTEM_RESOURCES ENABLE_JSON_LOGGING ENABLE_PROGRESS_BARS ENABLE_METRICS_COLLECTION; do
        local flag_value
        case "$flag" in
            ENABLE_PASSWORD_FILE) flag_value="$ENABLE_PASSWORD_FILE" ;;
            ENABLE_PASSWORD_COMMAND) flag_value="$ENABLE_PASSWORD_COMMAND" ;;
            ENABLE_BACKUP_VERIFICATION) flag_value="$ENABLE_BACKUP_VERIFICATION" ;;
            ENABLE_PERFORMANCE_MODE) flag_value="$ENABLE_PERFORMANCE_MODE" ;;
            ENABLE_DOCKER_STATE_CACHE) flag_value="$ENABLE_DOCKER_STATE_CACHE" ;;
            ENABLE_PARALLEL_PROCESSING) flag_value="$ENABLE_PARALLEL_PROCESSING" ;;
            CHECK_SYSTEM_RESOURCES) flag_value="$CHECK_SYSTEM_RESOURCES" ;;
            ENABLE_JSON_LOGGING) flag_value="$ENABLE_JSON_LOGGING" ;;
            ENABLE_PROGRESS_BARS) flag_value="$ENABLE_PROGRESS_BARS" ;;
            ENABLE_METRICS_COLLECTION) flag_value="$ENABLE_METRICS_COLLECTION" ;;
        esac
        
        if [[ -n "$flag_value" ]] && ! [[ "$flag_value" =~ ^(true|false)$ ]]; then
            log_warn "Invalid $flag value: $flag_value, must be 'true' or 'false'. Using default: false"
            case "$flag" in
                ENABLE_PASSWORD_FILE) ENABLE_PASSWORD_FILE="false" ;;
                ENABLE_PASSWORD_COMMAND) ENABLE_PASSWORD_COMMAND="false" ;;
                ENABLE_BACKUP_VERIFICATION) ENABLE_BACKUP_VERIFICATION="false" ;;
                ENABLE_PERFORMANCE_MODE) ENABLE_PERFORMANCE_MODE="false" ;;
                ENABLE_DOCKER_STATE_CACHE) ENABLE_DOCKER_STATE_CACHE="false" ;;
                ENABLE_PARALLEL_PROCESSING) ENABLE_PARALLEL_PROCESSING="false" ;;
                CHECK_SYSTEM_RESOURCES) CHECK_SYSTEM_RESOURCES="false" ;;
                ENABLE_JSON_LOGGING) ENABLE_JSON_LOGGING="false" ;;
                ENABLE_PROGRESS_BARS) ENABLE_PROGRESS_BARS="false" ;;
                ENABLE_METRICS_COLLECTION) ENABLE_METRICS_COLLECTION="false" ;;
            esac
        fi
    done
    
    # Validate verification depth
    if [[ -n "$VERIFICATION_DEPTH" ]] && ! [[ "$VERIFICATION_DEPTH" =~ ^(metadata|files|data)$ ]]; then
        log_warn "Invalid VERIFICATION_DEPTH value: $VERIFICATION_DEPTH, must be 'metadata', 'files', or 'data'. Using default: files"
        VERIFICATION_DEPTH="files"
    fi
    
    # Validate minimum disk space
    if ! [[ "$MIN_DISK_SPACE_MB" =~ ^[0-9]+$ ]] || [[ "$MIN_DISK_SPACE_MB" -lt 100 ]]; then
        log_warn "Invalid MIN_DISK_SPACE_MB value: $MIN_DISK_SPACE_MB, using default: 1024"
        MIN_DISK_SPACE_MB=1024
    fi
    
    # Validate Phase 2 numeric parameters
    if ! [[ "$MAX_PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [[ "$MAX_PARALLEL_JOBS" -lt 1 ]] || [[ "$MAX_PARALLEL_JOBS" -gt 10 ]]; then
        log_warn "Invalid MAX_PARALLEL_JOBS value: $MAX_PARALLEL_JOBS, must be 1-10. Using default: 2"
        MAX_PARALLEL_JOBS=2
    fi
    
    if ! [[ "$MEMORY_THRESHOLD_MB" =~ ^[0-9]+$ ]] || [[ "$MEMORY_THRESHOLD_MB" -lt 100 ]]; then
        log_warn "Invalid MEMORY_THRESHOLD_MB value: $MEMORY_THRESHOLD_MB, using default: 512"
        MEMORY_THRESHOLD_MB=512
    fi
    
    if ! [[ "$LOAD_THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$LOAD_THRESHOLD" -lt 10 ]] || [[ "$LOAD_THRESHOLD" -gt 100 ]]; then
        log_warn "Invalid LOAD_THRESHOLD value: $LOAD_THRESHOLD, must be 10-100. Using default: 80"
        LOAD_THRESHOLD=80
    fi
    
    # Set parallel jobs based on configuration
    if [[ "$ENABLE_PARALLEL_PROCESSING" == "true" ]]; then
        PARALLEL_JOBS="$MAX_PARALLEL_JOBS"
        log_debug "Parallel processing enabled with $PARALLEL_JOBS jobs"
    else
        PARALLEL_JOBS=1
        log_debug "Sequential processing mode (parallel processing disabled)"
    fi
    
    # Setup JSON logging if enabled
    if [[ "$ENABLE_JSON_LOGGING" == "true" ]]; then
        if [[ -z "$JSON_LOG_FILE" ]]; then
            JSON_LOG_FILE="$SCRIPT_DIR/logs/docker_backup.json"
            log_debug "Using default JSON log file: $JSON_LOG_FILE"
        fi
        
        # Ensure JSON log directory exists
        local json_log_dir
        json_log_dir="$(dirname "$JSON_LOG_FILE")"
        if [[ ! -d "$json_log_dir" ]]; then
            mkdir -p "$json_log_dir" || {
                log_warn "Cannot create JSON log directory: $json_log_dir, disabling JSON logging"
                ENABLE_JSON_LOGGING="false"
            }
        fi
    fi
    
    # Setup metrics collection if enabled
    if [[ "$ENABLE_METRICS_COLLECTION" == "true" ]]; then
        METRICS_FILE="$SCRIPT_DIR/logs/backup_metrics.json"
        log_debug "Metrics collection enabled: $METRICS_FILE"
    fi
    
    log_info "Configuration validation completed"
    log_debug "BACKUP_DIR: $BACKUP_DIR"
    log_debug "BACKUP_TIMEOUT: $BACKUP_TIMEOUT"
    log_debug "DOCKER_TIMEOUT: $DOCKER_TIMEOUT"
    log_debug "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY:0:20}..." # Only show first 20 chars for security
    log_debug "RESTIC_PASSWORD: [CONFIGURED]" # Don't log actual password
    log_debug "HOSTNAME: ${HOSTNAME:-[UNSET - will use system default]}"
    log_debug "KEEP_DAILY: ${KEEP_DAILY:-[UNSET]}"
    log_debug "KEEP_WEEKLY: ${KEEP_WEEKLY:-[UNSET]}"
    log_debug "KEEP_MONTHLY: ${KEEP_MONTHLY:-[UNSET]}"
    log_debug "KEEP_YEARLY: ${KEEP_YEARLY:-[UNSET]}"
    log_debug "AUTO_PRUNE: ${AUTO_PRUNE:-[UNSET - defaults to false]}"
    
    return $EXIT_SUCCESS
}

#######################################
# Phase 1: Security & Validation Functions
#######################################

# Enhanced input validation and sanitization
sanitize_input() {
    local input="$1"
    local type="${2:-path}"
    
    case "$type" in
        "path")
            # Remove potential path traversal attempts and dangerous characters
            echo "$input" | sed 's/\.\.\///g; s/[;&|`$()]//g'
            ;;
        "filename")
            # Remove dangerous characters for filenames
            echo "$input" | sed 's/[;&|`$()\/\\]//g'
            ;;
        "command")
            # Basic command sanitization (for password commands)
            echo "$input" | sed 's/[;&|`]//g'
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# Check file permissions for security
check_file_permissions() {
    local file_path="$1"
    local expected_mode="$2"
    
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    
    local actual_mode
    actual_mode="$(stat -c %a "$file_path" 2>/dev/null)"
    
    if [[ -z "$actual_mode" ]]; then
        log_error "Cannot determine permissions for: $file_path"
        return 1
    fi
    
    # Check if permissions are too open
    local first_digit="${actual_mode:0:1}"
    if [[ "$first_digit" -gt 6 ]]; then
        log_warn "File has overly permissive permissions: $file_path ($actual_mode)"
        log_warn "Consider using 'chmod 600 $file_path' for better security"
    fi
    
    return 0
}

# Enhanced password handling with multiple methods
setup_restic_password() {
    log_info "Setting up restic password authentication"
    
    # Priority order: password file > password command > direct password
    if [[ "$ENABLE_PASSWORD_FILE" == "true" && -n "$PASSWORD_FILE" ]]; then
        log_info "Using password file authentication"
        
        # Sanitize the password file path
        PASSWORD_FILE="$(sanitize_input "$PASSWORD_FILE" "path")"
        
        if [[ ! -f "$PASSWORD_FILE" ]]; then
            log_error "Password file not found: $PASSWORD_FILE"
            return $EXIT_CONFIG_ERROR
        fi
        
        if [[ ! -r "$PASSWORD_FILE" ]]; then
            log_error "Password file not readable: $PASSWORD_FILE"
            return $EXIT_CONFIG_ERROR
        fi
        
        # Check file permissions for security
        check_file_permissions "$PASSWORD_FILE" "600"
        
        # Export the password file for restic
        export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"
        unset RESTIC_PASSWORD  # Clear password variable for security
        log_debug "Using password file: ${PASSWORD_FILE:0:20}..."
        
    elif [[ "$ENABLE_PASSWORD_COMMAND" == "true" && -n "$PASSWORD_COMMAND" ]]; then
        log_info "Using password command authentication"
        
        # Sanitize the password command
        PASSWORD_COMMAND="$(sanitize_input "$PASSWORD_COMMAND" "command")"
        
        # Test that the command works
        local test_password
        if ! test_password="$(eval "$PASSWORD_COMMAND" 2>/dev/null)"; then
            log_error "Password command failed to execute: $PASSWORD_COMMAND"
            return $EXIT_CONFIG_ERROR
        fi
        
        if [[ -z "$test_password" ]]; then
            log_error "Password command returned empty password: $PASSWORD_COMMAND"
            return $EXIT_CONFIG_ERROR
        fi
        
        # Export the password command for restic
        export RESTIC_PASSWORD_COMMAND="$PASSWORD_COMMAND"
        unset RESTIC_PASSWORD  # Clear password variable for security
        log_debug "Using password command: ${PASSWORD_COMMAND:0:20}..."
        
    elif [[ -n "$RESTIC_PASSWORD" ]]; then
        log_info "Using direct password authentication"
        export RESTIC_PASSWORD
        log_debug "Using direct password authentication"
        
    else
        log_error "No valid password method configured"
        return $EXIT_CONFIG_ERROR
    fi
    
    return $EXIT_SUCCESS
}

# Disk space monitoring
check_disk_space() {
    local path="$1"
    local min_space_mb="${2:-$MIN_DISK_SPACE_MB}"
    
    log_debug "Checking disk space for: $path (minimum: ${min_space_mb}MB)"
    
    if [[ ! -d "$path" ]]; then
        log_error "Path does not exist for disk space check: $path"
        return 1
    fi
    
    # Get available space in MB
    local available_mb
    available_mb="$(df -BM "$path" | awk 'NR==2 {print $4}' | sed 's/M//')"
    
    if [[ -z "$available_mb" || ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log_warn "Cannot determine available disk space for: $path"
        return 0  # Don't fail on disk space check errors
    fi
    
    log_debug "Available disk space: ${available_mb}MB"
    
    if [[ "$available_mb" -lt "$min_space_mb" ]]; then
        log_error "Insufficient disk space: ${available_mb}MB available, ${min_space_mb}MB required"
        return 1
    fi
    
    log_debug "Disk space check passed: ${available_mb}MB available"
    return 0
}

# Repository health check
check_repository_health() {
    log_info "Performing repository health check"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform repository health check"
        return $EXIT_SUCCESS
    fi
    
    # Check if repository is accessible
    if ! restic snapshots --quiet >/dev/null 2>&1; then
        log_error "Repository health check failed: cannot access repository"
        return $EXIT_BACKUP_ERROR
    fi
    
    # Check repository integrity (quick check)
    local check_output
    if ! check_output="$(restic check --read-data-subset=1% 2>&1)"; then
        log_warn "Repository integrity check found issues:"
        echo "$check_output" | while IFS= read -r line; do
            log_warn "  $line"
        done
        return $EXIT_BACKUP_ERROR
    fi
    
    log_info "Repository health check completed successfully"
    return $EXIT_SUCCESS
}

# Backup verification function
verify_backup() {
    local dir_name="$1"
    local verification_depth="${2:-$VERIFICATION_DEPTH}"
    
    if [[ "$ENABLE_BACKUP_VERIFICATION" != "true" ]]; then
        log_debug "Backup verification disabled, skipping for: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    log_info "Verifying backup for: $dir_name (depth: $verification_depth)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify backup for: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    # Get the latest snapshot for this directory
    local latest_snapshot
    latest_snapshot="$(restic snapshots --tag "$dir_name" --latest 1 --json 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null)"
    
    if [[ -z "$latest_snapshot" ]]; then
        log_error "Cannot find latest snapshot for verification: $dir_name"
        return $EXIT_BACKUP_ERROR
    fi
    
    log_debug "Verifying snapshot: $latest_snapshot"
    
    case "$verification_depth" in
        "metadata")
            # Quick metadata verification
            if restic ls "$latest_snapshot" >/dev/null 2>&1; then
                log_info "Backup verification passed (metadata): $dir_name"
                return $EXIT_SUCCESS
            else
                log_error "Backup verification failed (metadata): $dir_name"
                return $EXIT_BACKUP_ERROR
            fi
            ;;
        "files")
            # Verify file listing and basic integrity
            local ls_output
            if ls_output="$(restic ls "$latest_snapshot" 2>&1)"; then
                local file_count
                file_count="$(echo "$ls_output" | wc -l)"
                log_info "Backup verification passed (files): $dir_name ($file_count files)"
                return $EXIT_SUCCESS
            else
                log_error "Backup verification failed (files): $dir_name"
                log_error "Verification error: $ls_output"
                return $EXIT_BACKUP_ERROR
            fi
            ;;
        "data")
            # Deep verification with data integrity check
            local check_output
            if check_output="$(restic check --read-data "$latest_snapshot" 2>&1)"; then
                log_info "Backup verification passed (data): $dir_name"
                return $EXIT_SUCCESS
            else
                log_error "Backup verification failed (data): $dir_name"
                log_error "Verification error: $check_output"
                return $EXIT_BACKUP_ERROR
            fi
            ;;
        *)
            log_warn "Unknown verification depth: $verification_depth, using 'files'"
            verify_backup "$dir_name" "files"
            return $?
            ;;
    esac
}

#######################################
# Phase 2: Resource Monitoring & Performance Functions
#######################################

# System resource monitoring
check_system_resources() {
    if [[ "$CHECK_SYSTEM_RESOURCES" != "true" ]]; then
        log_debug "System resource monitoring disabled"
        return 0
    fi
    
    log_info "Checking system resources"
    
    # Check available memory
    local available_memory_mb
    available_memory_mb="$(free -m | awk 'NR==2{print $7}')"
    
    if [[ -z "$available_memory_mb" || ! "$available_memory_mb" =~ ^[0-9]+$ ]]; then
        log_warn "Cannot determine available memory, skipping memory check"
    else
        log_debug "Available memory: ${available_memory_mb}MB"
        if [[ "$available_memory_mb" -lt "$MEMORY_THRESHOLD_MB" ]]; then
            log_warn "Low available memory: ${available_memory_mb}MB (threshold: ${MEMORY_THRESHOLD_MB}MB)"
            log_warn "Consider increasing memory or adjusting MEMORY_THRESHOLD_MB"
        fi
    fi
    
    # Check system load
    local load_1min
    load_1min="$(uptime | awk '{print $(NF-2)}' | sed 's/,//')"
    
    if [[ -n "$load_1min" ]]; then
        # Convert load to percentage (assuming single core baseline)
        local load_percentage
        load_percentage="$(echo "$load_1min * 100 / 1" | bc -l 2>/dev/null | cut -d. -f1 2>/dev/null || echo "0")"
        
        log_debug "System load (1min): $load_1min (${load_percentage}%)"
        if [[ "$load_percentage" -gt "$LOAD_THRESHOLD" ]]; then
            log_warn "High system load: ${load_percentage}% (threshold: ${LOAD_THRESHOLD}%)"
            log_warn "Consider running backup during lower system load periods"
        fi
    fi
    
    return 0
}

# Docker state caching for performance optimization
initialize_docker_cache() {
    if [[ "$ENABLE_DOCKER_STATE_CACHE" != "true" ]]; then
        log_debug "Docker state caching disabled"
        return 0
    fi
    
    DOCKER_STATE_CACHE_FILE="$SCRIPT_DIR/logs/docker_state_cache.tmp"
    log_debug "Initializing Docker state cache: $DOCKER_STATE_CACHE_FILE"
    
    # Clear any existing cache
    rm -f "$DOCKER_STATE_CACHE_FILE"
    
    # Pre-cache Docker state information for all directories
    log_debug "Pre-caching Docker states for enabled directories"
    {
        echo "# Docker State Cache - $(date)"
        echo "# Format: directory_name=state"
        for dir_name in "${!DIRLIST_ARRAY[@]}"; do
            if [[ "${DIRLIST_ARRAY[$dir_name]}" == "true" ]]; then
                local dir_path="$BACKUP_DIR/$dir_name"
                if [[ -d "$dir_path" ]]; then
                    local running_containers=0
                    if cd "$dir_path" 2>/dev/null; then
                        local ps_output
                        ps_output="$(docker compose ps --services --filter "status=running" 2>/dev/null || echo "")"
                        running_containers="$(echo "$ps_output" | awk 'NF' | wc -l)"
                        cd - >/dev/null
                    fi
                    
                    if [[ "$running_containers" -gt 0 ]]; then
                        echo "$dir_name=running"
                        log_debug "Cached state: $dir_name=running"
                    else
                        echo "$dir_name=stopped"
                        log_debug "Cached state: $dir_name=stopped"
                    fi
                fi
            fi
        done
    } > "$DOCKER_STATE_CACHE_FILE"
    
    log_debug "Docker state cache initialized"
    return 0
}

# Get cached Docker state (performance optimization)
get_cached_docker_state() {
    local dir_name="$1"
    
    if [[ "$ENABLE_DOCKER_STATE_CACHE" != "true" || ! -f "$DOCKER_STATE_CACHE_FILE" ]]; then
        return 1  # Cache not available
    fi
    
    local cached_state
    cached_state="$(grep "^$dir_name=" "$DOCKER_STATE_CACHE_FILE" 2>/dev/null | cut -d= -f2)"
    
    if [[ -n "$cached_state" ]]; then
        log_debug "Using cached Docker state for $dir_name: $cached_state"
        echo "$cached_state"
        return 0
    fi
    
    return 1  # Not found in cache
}

# Performance-optimized restic backup with optimization flags
backup_single_directory_optimized() {
    local dir_name="$1"
    local dir_path="$2"
    
    log_info "Starting optimized restic backup for: $dir_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup directory with optimizations: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    # Ensure restic environment variables are exported
    export RESTIC_REPOSITORY
    if [[ -n "$RESTIC_PASSWORD" ]]; then
        export RESTIC_PASSWORD
    fi
    
    local backup_start_time
    backup_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Build optimized backup command
    local backup_cmd=(
        timeout "$BACKUP_TIMEOUT"
        restic backup
        --verbose
        --tag "docker-backup"
        --tag "selective-backup"
        --tag "$dir_name"
        --tag "$(date '+%Y-%m-%d')"
    )
    
    # Add performance optimizations if enabled
    if [[ "$ENABLE_PERFORMANCE_MODE" == "true" ]]; then
        backup_cmd+=(
            --one-file-system
            --exclude-caches
            --exclude-if-present .resticignore
        )
        log_debug "Added performance optimization flags for $dir_name"
    fi
    
    # Add hostname parameter if configured
    if [[ -n "$HOSTNAME" ]]; then
        backup_cmd+=(--hostname "$HOSTNAME")
        log_debug "Using custom hostname for backup: $HOSTNAME"
    else
        log_debug "Using system default hostname for backup"
    fi
    
    # Add the directory path as the final argument
    backup_cmd+=("$dir_path")
    
    log_info "Executing optimized backup command for $dir_name"
    log_debug "Backup command: ${backup_cmd[*]}"
    log_progress "Starting optimized restic backup - output will be displayed below:"
    
    # Run restic with output visible to user and logged to file
    local restic_output_file
    restic_output_file="$(mktemp)"
    
    # Run restic command with real-time output display and logging
    if "${backup_cmd[@]}" 2>&1 | tee "$restic_output_file"; then
        # Also append the output to our log file with proper formatting
        while IFS= read -r line; do
            log_message "RESTIC" "$line"
        done < "$restic_output_file"
        rm -f "$restic_output_file"
        local backup_end_time
        backup_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
        log_info "Optimized backup completed successfully for: $dir_name"
        log_debug "Backup start time: $backup_start_time"
        log_debug "Backup end time: $backup_end_time"
        return $EXIT_SUCCESS
    else
        local exit_code=$?
        # Also append the output to our log file with proper formatting
        while IFS= read -r line; do
            log_message "RESTIC" "$line"
        done < "$restic_output_file"
        rm -f "$restic_output_file"
        log_error "Optimized backup failed for $dir_name with exit code: $exit_code"
        return $EXIT_BACKUP_ERROR
    fi
}

# Parallel processing controller (for future expansion)
process_directories_parallel() {
    local enabled_dirs=("$@")
    
    if [[ "$ENABLE_PARALLEL_PROCESSING" != "true" || "$PARALLEL_JOBS" -eq 1 ]]; then
        log_debug "Parallel processing disabled, using sequential processing"
        return 1  # Fall back to sequential processing
    fi
    
    log_info "Parallel processing enabled with $PARALLEL_JOBS concurrent jobs"
    log_warn "Parallel processing is experimental and may cause resource contention"
    
    # For now, return 1 to fall back to sequential processing
    # Future implementation would use job control and process management
    return 1
}

#######################################
# Phase 3: Enhanced Monitoring & User Experience Functions
#######################################

# JSON logging function
log_json() {
    local event_type="$1"
    local directory="${2:-}"
    local status="${3:-}"
    local details="${4:-}"
    
    if [[ "$ENABLE_JSON_LOGGING" != "true" || -z "$JSON_LOG_FILE" ]]; then
        return 0
    fi
    
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    
    local json_entry
    json_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "event_type": "$event_type",
  "directory": "$directory",
  "status": "$status",
  "details": "$details",
  "script_pid": $$
}
EOF
    )
    
    echo "$json_entry" >> "$JSON_LOG_FILE" 2>/dev/null || {
        log_debug "Failed to write to JSON log file: $JSON_LOG_FILE"
    }
}

# Progress bar functionality
show_progress() {
    local current="$1"
    local total="$2"
    local description="${3:-Processing}"
    
    if [[ "$ENABLE_PROGRESS_BARS" != "true" ]]; then
        return 0
    fi
    
    local percentage=0
    if [[ $total -gt 0 ]]; then
        percentage=$((current * 100 / total))
    fi
    
    local bar_length=50
    local filled_length=$((percentage * bar_length / 100))
    local empty_length=$((bar_length - filled_length))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty_length; i++)); do
        bar+="░"
    done
    
    printf "\r${CYAN}%s: [%s] %d%% (%d/%d)${NC}" "$description" "$bar" "$percentage" "$current" "$total"
    
    if [[ $current -eq $total ]]; then
        printf "\n"
    fi
}

# Metrics collection
collect_metric() {
    local metric_type="$1"
    local value="$2"
    local directory="${3:-}"
    
    if [[ "$ENABLE_METRICS_COLLECTION" != "true" || -z "$METRICS_FILE" ]]; then
        return 0
    fi
    
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    
    local metric_entry
    metric_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "metric_type": "$metric_type",
  "value": "$value",
  "directory": "$directory",
  "script_pid": $$
}
EOF
    )
    
    echo "$metric_entry" >> "$METRICS_FILE" 2>/dev/null || {
        log_debug "Failed to write to metrics file: $METRICS_FILE"
    }
}

# Initialize metrics collection
initialize_metrics() {
    if [[ "$ENABLE_METRICS_COLLECTION" != "true" || -z "$METRICS_FILE" ]]; then
        return 0
    fi
    
    log_debug "Initializing metrics collection: $METRICS_FILE"
    
    # Create metrics file header
    {
        echo "{"
        echo "  \"backup_session\": {"
        echo "    \"start_time\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
        echo "    \"script_version\": \"2.0\","
        echo "    \"pid\": $$"
        echo "  },"
        echo "  \"metrics\": ["
    } > "$METRICS_FILE" 2>/dev/null || {
        log_warn "Cannot initialize metrics file: $METRICS_FILE, disabling metrics collection"
        ENABLE_METRICS_COLLECTION="false"
        return 1
    }
    
    collect_metric "session_start" "$(date +%s)"
    return 0
}

# Finalize metrics collection
finalize_metrics() {
    if [[ "$ENABLE_METRICS_COLLECTION" != "true" || -z "$METRICS_FILE" ]]; then
        return 0
    fi
    
    collect_metric "session_end" "$(date +%s)"
    
    # Close metrics file
    {
        echo "  ]"
        echo "}"
    } >> "$METRICS_FILE" 2>/dev/null || {
        log_debug "Failed to finalize metrics file: $METRICS_FILE"
    }
    
    log_debug "Metrics collection finalized"
}

# Enhanced logging with JSON support
log_message_enhanced() {
    local level="$1"
    shift
    local message="$*"
    
    # Call original log_message function
    log_message "$level" "$message"
    
    # Also log to JSON if enabled
    case "$level" in
        ERROR|WARN)
            log_json "log_entry" "" "$level" "$message"
            ;;
        PROGRESS)
            log_json "progress" "" "info" "$message"
            ;;
    esac
}

# Status reporting for monitoring integration
generate_status_report() {
    local status="$1"
    local details="${2:-}"
    
    local report_file="$SCRIPT_DIR/logs/backup_status.json"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    
    cat > "$report_file" <<EOF
{
  "timestamp": "$timestamp",
  "status": "$status",
  "details": "$details",
  "script_pid": $$,
  "config_file": "$CONFIG_FILE",
  "backup_dir": "$BACKUP_DIR"
}
EOF
    
    log_debug "Generated status report: $report_file"
}

# List recent backup snapshots
list_backups() {
    log_info "Listing recent backup snapshots"
    
    # Ensure restic is configured
    if ! check_restic; then
        log_error "Cannot access restic repository"
        return $EXIT_BACKUP_ERROR
    fi
    
    echo
    echo -e "${GREEN}Recent Backup Snapshots:${NC}"
    echo "=========================="
    
    # List snapshots grouped by directory tag
    local snapshots_output
    snapshots_output="$(restic snapshots --json 2>/dev/null)"
    
    if [[ -z "$snapshots_output" || "$snapshots_output" == "null" ]]; then
        echo "No snapshots found in repository"
        return 0
    fi
    
    # Process snapshots using basic text processing (avoiding jq dependency)
    echo "$snapshots_output" | grep -E '"tags"|"time"|"short_id"' | \
    while IFS= read -r line; do
        if [[ "$line" =~ \"tags\" ]]; then
            # Extract directory name from tags
            local dir_tag
            dir_tag="$(echo "$line" | sed -n 's/.*"tags":\[.*"\([^"]*\)".*\].*/\1/p' | head -1)"
            if [[ -n "$dir_tag" && "$dir_tag" != "docker-backup" && "$dir_tag" != "selective-backup" ]]; then
                echo -n -e "${CYAN}Directory: $dir_tag${NC} - "
            fi
        elif [[ "$line" =~ \"short_id\" ]]; then
            local snapshot_id
            snapshot_id="$(echo "$line" | sed 's/.*"short_id": *"\([^"]*\)".*/\1/')"
            echo -n "ID: $snapshot_id - "
        elif [[ "$line" =~ \"time\" ]]; then
            local timestamp
            timestamp="$(echo "$line" | sed 's/.*"time": *"\([^"]*\)".*/\1/' | cut -dT -f1,2 | tr T ' ')"
            echo "Time: $timestamp"
        fi
    done
    
    echo
    return 0
}

# Preview restore for a directory
restore_preview() {
    local dir_name="$1"
    
    if [[ -z "$dir_name" ]]; then
        log_error "Directory name required for restore preview"
        echo "Usage: $SCRIPT_NAME --restore-preview DIRECTORY_NAME"
        return $EXIT_CONFIG_ERROR
    fi
    
    log_info "Generating restore preview for directory: $dir_name"
    
    # Ensure restic is configured
    if ! check_restic; then
        log_error "Cannot access restic repository"
        return $EXIT_BACKUP_ERROR
    fi
    
    # Find the latest snapshot for this directory
    local latest_snapshot
    latest_snapshot="$(restic snapshots --tag "$dir_name" --latest 1 --json 2>/dev/null | grep -o '"short_id":"[^"]*"' | head -1 | cut -d'"' -f4)"
    
    if [[ -z "$latest_snapshot" ]]; then
        log_error "No snapshots found for directory: $dir_name"
        return $EXIT_BACKUP_ERROR
    fi
    
    echo
    echo -e "${GREEN}Restore Preview for Directory: $dir_name${NC}"
    echo "==============================================="
    echo "Latest snapshot ID: $latest_snapshot"
    echo
    echo -e "${YELLOW}Files that would be restored:${NC}"
    
    # List files in the snapshot
    if restic ls "$latest_snapshot" 2>/dev/null; then
        echo
        echo -e "${GREEN}Restore preview completed successfully${NC}"
        echo "To perform actual restore:"
        echo "  restic restore $latest_snapshot --target /path/to/restore/location"
    else
        log_error "Failed to list files in snapshot: $latest_snapshot"
        return $EXIT_BACKUP_ERROR
    fi
    
    return 0
}

#######################################
# Phase 4: Configuration Management Functions
#######################################

# Generate configuration template
generate_config_template() {
    local template_file="${1:-$SCRIPT_DIR/backup.conf.template}"
    
    log_info "Generating configuration template: $template_file"
    
    if [[ -f "$template_file" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_warn "Template file already exists: $template_file"
        echo "Overwrite existing template? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Template generation cancelled"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate configuration template: $template_file"
        return 0
    fi
    
    cat > "$template_file" << 'EOF'
# Docker Stack 3-Stage Backup System Configuration Template
# Copy this file to backup.conf and customize for your environment

#######################################
# Core Backup Settings (Required)
#######################################

# Directory containing Docker compose stacks to backup
# This should be the parent directory containing subdirectories with docker-compose.yml files
BACKUP_DIR=/opt/docker-stacks

# Restic repository configuration (local path, sftp://, s3://, etc.)
RESTIC_REPOSITORY=/path/to/restic/repository

# Restic repository password
# WARNING: Stored in plain text - use file permissions (chmod 600) to protect
RESTIC_PASSWORD=your-secure-password

#######################################
# Enhanced Security Options (Phase 1)
#######################################

# Enable password file support (more secure than inline password)
# ENABLE_PASSWORD_FILE=true
# RESTIC_PASSWORD_FILE=/path/to/password/file

# Enable password command support (most secure option)
# ENABLE_PASSWORD_COMMAND=true
# RESTIC_PASSWORD_COMMAND="pass show backup/restic"

#######################################
# Backup Verification (Phase 1)
#######################################

# Enable post-backup verification
ENABLE_BACKUP_VERIFICATION=true

# Verification depth: metadata, files, or data
VERIFICATION_DEPTH=files

#######################################
# Resource Monitoring (Phase 2)
#######################################

# Minimum required disk space in MB
MIN_DISK_SPACE_MB=1024

# Enable system resource monitoring
CHECK_SYSTEM_RESOURCES=true

# Memory threshold in MB for warnings
MEMORY_THRESHOLD_MB=512

# System load threshold percentage for warnings
LOAD_THRESHOLD=80

#######################################
# Performance Options (Phase 2)
#######################################

# Enable performance mode (experimental features)
ENABLE_PERFORMANCE_MODE=false

# Enable Docker state caching to reduce API calls
ENABLE_DOCKER_STATE_CACHE=false

# Enable parallel processing (experimental - use with caution)
ENABLE_PARALLEL_PROCESSING=false
MAX_PARALLEL_JOBS=2

#######################################
# Enhanced Monitoring (Phase 3)
#######################################

# Enable JSON logging for monitoring systems
ENABLE_JSON_LOGGING=false
JSON_LOG_FILE=/path/to/json/backup.log

# Enable progress bars during operations
ENABLE_PROGRESS_BARS=true

# Enable metrics collection
ENABLE_METRICS_COLLECTION=false
METRICS_FILE=/path/to/metrics/backup_metrics.txt

#######################################
# Timeouts and Limits
#######################################

# Backup timeout in seconds (default: 3600 = 1 hour)
BACKUP_TIMEOUT=3600

# Docker command timeout in seconds (default: 30)
DOCKER_TIMEOUT=30

#######################################
# Retention Policy (Optional)
#######################################

# Custom hostname for backup identification
# HOSTNAME=backup-server

# Retention settings
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
KEEP_YEARLY=3

# Auto-prune after successful backups
AUTO_PRUNE=false

#######################################
# Example Configurations
#######################################

# Small home setup:
# BACKUP_DIR=/home/user/docker-projects
# BACKUP_TIMEOUT=1800
# RESTIC_REPOSITORY=/home/user/backups/restic-repo

# Large production setup:
# BACKUP_DIR=/srv/docker-stacks
# BACKUP_TIMEOUT=7200
# RESTIC_REPOSITORY=sftp:backup-server:/srv/backups/restic-repo
# ENABLE_BACKUP_VERIFICATION=true
# CHECK_SYSTEM_RESOURCES=true

# High-security setup:
# ENABLE_PASSWORD_FILE=true
# RESTIC_PASSWORD_FILE=/etc/backup/restic.password
# VERIFICATION_DEPTH=data
# MIN_DISK_SPACE_MB=5120
EOF
    
    if [[ $? -eq 0 ]]; then
        chmod 644 "$template_file"
        log_info "Configuration template created successfully: $template_file"
        log_info "To use: cp $template_file backup.conf && chmod 600 backup.conf"
        return 0
    else
        log_error "Failed to create configuration template"
        return $EXIT_CONFIG_ERROR
    fi
}

# Enhanced configuration validation
validate_configuration() {
    log_debug "Performing enhanced configuration validation"
    
    local validation_errors=0
    local warnings=0
    
    # Validate required fields
    if [[ -z "$BACKUP_DIR" ]]; then
        log_error "BACKUP_DIR is required but not set"
        ((validation_errors++))
    elif [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "BACKUP_DIR does not exist: $BACKUP_DIR"
        ((validation_errors++))
    fi
    
    if [[ -z "$RESTIC_REPOSITORY" ]]; then
        log_error "RESTIC_REPOSITORY is required but not set"
        ((validation_errors++))
    fi
    
    # Validate password configuration
    local password_methods=0
    [[ -n "$RESTIC_PASSWORD" ]] && ((password_methods++))
    [[ -n "$PASSWORD_FILE" ]] && ((password_methods++))
    [[ -n "$PASSWORD_COMMAND" ]] && ((password_methods++))
    
    if [[ $password_methods -eq 0 ]]; then
        log_error "No restic password configured (RESTIC_PASSWORD, RESTIC_PASSWORD_FILE, or RESTIC_PASSWORD_COMMAND required)"
        ((validation_errors++))
    elif [[ $password_methods -gt 1 ]]; then
        log_warn "Multiple password methods configured - using priority order"
        ((warnings++))
    fi
    
    # Validate numeric values
    for var in BACKUP_TIMEOUT DOCKER_TIMEOUT MIN_DISK_SPACE_MB MEMORY_THRESHOLD_MB LOAD_THRESHOLD; do
        local value
        eval "value=\$$var"
        if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
            log_error "Invalid numeric value for $var: $value"
            ((validation_errors++))
        fi
    done
    
    # Validate timeout ranges
    if [[ -n "$BACKUP_TIMEOUT" && ( "$BACKUP_TIMEOUT" -lt 60 || "$BACKUP_TIMEOUT" -gt 86400 ) ]]; then
        log_warn "BACKUP_TIMEOUT outside recommended range (60-86400 seconds): $BACKUP_TIMEOUT"
        ((warnings++))
    fi
    
    if [[ -n "$DOCKER_TIMEOUT" && ( "$DOCKER_TIMEOUT" -lt 5 || "$DOCKER_TIMEOUT" -gt 300 ) ]]; then
        log_warn "DOCKER_TIMEOUT outside recommended range (5-300 seconds): $DOCKER_TIMEOUT"
        ((warnings++))
    fi
    
    # Validate file permissions
    if [[ -f "$CONFIG_FILE" ]]; then
        local perms
        perms="$(stat -c %a "$CONFIG_FILE" 2>/dev/null)"
        if [[ "${perms:1:2}" != "00" ]]; then
            log_warn "Configuration file has permissive permissions: $CONFIG_FILE ($perms)"
            log_warn "Consider: chmod 600 $CONFIG_FILE"
            ((warnings++))
        fi
    fi
    
    # Summary
    if [[ $validation_errors -gt 0 ]]; then
        log_error "Configuration validation failed with $validation_errors errors"
        return $EXIT_CONFIG_ERROR
    elif [[ $warnings -gt 0 ]]; then
        log_warn "Configuration validation completed with $warnings warnings"
        return 0
    else
        log_info "Configuration validation passed successfully"
        return 0
    fi
}

#######################################
# Phase 4: Operational Features
#######################################

# Generate health check report
generate_health_report() {
    local health_file="${1:-$SCRIPT_DIR/logs/backup_health.json}"
    local health_dir
    health_dir="$(dirname "$health_file")"
    
    log_debug "Generating health report: $health_file"
    
    # Ensure health directory exists
    if [[ ! -d "$health_dir" ]]; then
        mkdir -p "$health_dir" || {
            log_error "Cannot create health report directory: $health_dir"
            return 1
        }
    fi
    
    # Get last run information
    local last_run_timestamp=""
    local last_run_status="unknown"
    local failed_directories=0
    local total_directories=0
    
    if [[ -f "$LOG_FILE" ]]; then
        last_run_timestamp=$(grep "Backup completed" "$LOG_FILE" | tail -1 | awk '{print $1" "$2}' | sed 's/\[//g')
        if grep -q "failed: 0" "$LOG_FILE" | tail -1; then
            last_run_status="success"
        elif grep -q "failed:" "$LOG_FILE" | tail -1; then
            last_run_status="partial_failure"
            failed_directories=$(grep "failed:" "$LOG_FILE" | tail -1 | sed 's/.*failed: \([0-9]*\).*/\1/')
        fi
    fi
    
    # Count enabled directories
    if [[ -f "$DIRLIST_FILE" ]]; then
        total_directories=$(grep "=true" "$DIRLIST_FILE" | wc -l)
    fi
    
    # Get repository information
    local repo_size=""
    local snapshot_count=""
    if restic snapshots --quiet >/dev/null 2>&1; then
        snapshot_count=$(restic snapshots --json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
        repo_size=$(restic stats --json 2>/dev/null | jq -r '.total_size // "unknown"' 2>/dev/null || echo "unknown")
    fi
    
    # Generate JSON health report
    local health_report
    health_report=$(cat <<EOF
{
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "script_version": "2.0",
    "status": "$last_run_status",
    "last_run": {
        "timestamp": "$last_run_timestamp",
        "status": "$last_run_status",
        "failed_directories": $failed_directories,
        "total_directories": $total_directories
    },
    "repository": {
        "path": "${RESTIC_REPOSITORY:0:50}...",
        "total_size": "$repo_size",
        "snapshot_count": $snapshot_count
    },
    "configuration": {
        "backup_dir": "$BACKUP_DIR",
        "verification_enabled": "$ENABLE_BACKUP_VERIFICATION",
        "verification_depth": "$VERIFICATION_DEPTH",
        "resource_monitoring": "$CHECK_SYSTEM_RESOURCES",
        "json_logging": "$ENABLE_JSON_LOGGING"
    },
    "system": {
        "hostname": "$(hostname)",
        "disk_space_mb": $(df -BM "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/M//' || echo "0"),
        "load_average": "$(uptime | awk '{print $(NF-2)}' | sed 's/,//')",
        "script_pid": $$
    }
}
EOF
    )
    
    if echo "$health_report" > "$health_file"; then
        log_debug "Health report generated successfully"
        return 0
    else
        log_error "Failed to generate health report"
        return 1
    fi
}

# Notification system
send_notification() {
    local event_type="$1"
    local message="$2"
    local details="${3:-}"
    
    log_debug "Notification: $event_type - $message"
    
    # Placeholder for notification integration
    # Users can customize this function for their notification needs
    
    case "$event_type" in
        "backup_started")
            log_info "📋 Backup process started"
            ;;
        "backup_completed")
            if [[ "$details" == "success" ]]; then
                log_info "✅ Backup completed successfully"
            else
                log_warn "⚠️ Backup completed with issues: $details"
            fi
            ;;
        "backup_failed")
            log_error "❌ Backup process failed: $message"
            ;;
        "low_disk_space")
            log_warn "💾 Low disk space warning: $message"
            ;;
        "repository_issue")
            log_error "🗃️ Repository health issue: $message"
            ;;
        *)
            log_info "📢 Notification: $message"
            ;;
    esac
    
    # Example integrations (commented out - users can enable as needed):
    # Email: echo "$message" | mail -s "Backup $event_type" admin@example.com
    # Slack: curl -X POST -H 'Content-type: application/json' --data '{"text":"'"$message"'"}' $SLACK_WEBHOOK
    # Syslog: logger -t docker-backup "$event_type: $message"
    
    return 0
}

#######################################
# Directory List Management
#######################################

# Scan directories and manage .dirlist file
scan_directories() {
    log_progress "Scanning target directory for Docker compose directories"
    log_info "Scanning directory: $BACKUP_DIR"
    
    local found_dirs=()
    local dir_count=0
    
    # Find all top-level subdirectories containing docker-compose files
    while IFS= read -r -d '' dir; do
        local dir_name
        dir_name="$(basename "$dir")"
        
        # Skip hidden directories
        if [[ "$dir_name" =~ ^\..*$ ]]; then
            log_debug "Skipping hidden directory: $dir"
            continue
        fi
        
        # Check if directory contains docker-compose files
        if [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]] || [[ -f "$dir/compose.yml" ]] || [[ -f "$dir/compose.yaml" ]]; then
            found_dirs+=("$dir_name")
            ((dir_count++))
            log_debug "Found compose directory: $dir_name"
        else
            log_debug "No compose file found in: $dir_name"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -not -path "$BACKUP_DIR" -print0 2>/dev/null || true)
    
    log_info "Found $dir_count Docker compose directories"
    
    # Update .dirlist file
    update_dirlist "${found_dirs[@]}"
    
    return $EXIT_SUCCESS
}

# Load directory list from .dirlist file into global array
load_dirlist() {
    if [[ ! -f "$DIRLIST_FILE" ]]; then
        log_warn "Directory list file not found: $DIRLIST_FILE"
        return 1
    fi
    
    log_debug "Loading directory list from: $DIRLIST_FILE"
    
    # Initialize counter for validation
    local loaded_count=0
    
    # Read the dirlist file and populate the global associative array
    while IFS='=' read -r dir_name enabled; do
        # Skip comments and empty lines
        if [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]]; then
            continue
        fi
        
        # Validate format
        if [[ "$enabled" =~ ^(true|false)$ ]]; then
            log_debug "Loading: $dir_name=$enabled"
            # Use global array instead of nameref
            DIRLIST_ARRAY["$dir_name"]="$enabled"
            ((loaded_count++))
            log_debug "Loaded: $dir_name=$enabled (count: $loaded_count)"
        else
            log_warn "Invalid format in dirlist: $dir_name=$enabled"
        fi
    done < "$DIRLIST_FILE"
    
    log_debug "Load completed. Total entries loaded: $loaded_count"
    log_debug "Array size after loading: ${#DIRLIST_ARRAY[@]}"
    
    return $EXIT_SUCCESS
}

# Load directory list from .dirlist file into a local array (for update_dirlist function)
load_dirlist_local() {
    local -n local_dirlist_ref=$1
    
    if [[ ! -f "$DIRLIST_FILE" ]]; then
        log_warn "Directory list file not found: $DIRLIST_FILE"
        return 1
    fi
    
    log_debug "Loading directory list into local array from: $DIRLIST_FILE"
    
    # Read the dirlist file and populate the local associative array
    while IFS='=' read -r dir_name enabled; do
        # Skip comments and empty lines
        if [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]]; then
            continue
        fi
        
        # Validate format
        if [[ "$enabled" =~ ^(true|false)$ ]]; then
            local_dirlist_ref["$dir_name"]="$enabled"
            log_debug "Loaded to local array: $dir_name=$enabled"
        else
            log_warn "Invalid format in dirlist: $dir_name=$enabled"
        fi
    done < "$DIRLIST_FILE"
    
    return $EXIT_SUCCESS
}

# Update .dirlist file with current directories
update_dirlist() {
    local current_dirs=("$@")
    local -A existing_dirlist
    local changes_made=false
    
    log_progress "Updating directory list file"
    
    # Load existing dirlist if it exists
    if [[ -f "$DIRLIST_FILE" ]]; then
        load_dirlist_local existing_dirlist || true
    fi
    
    # Create temporary file for new dirlist
    local temp_dirlist
    temp_dirlist="$(mktemp)"
    
    # Write header
    cat > "$temp_dirlist" << 'EOF'
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup
EOF
    
    # Process current directories
    for dir_name in "${current_dirs[@]}"; do
        if [[ -n "${existing_dirlist[$dir_name]:-}" ]]; then
            # Directory exists in current list, keep existing setting
            echo "$dir_name=${existing_dirlist[$dir_name]}" >> "$temp_dirlist"
            log_debug "Kept existing setting: $dir_name=${existing_dirlist[$dir_name]}"
        else
            # New directory, default to false (opt-in approach)
            echo "$dir_name=false" >> "$temp_dirlist"
            log_info "Added new directory (disabled by default): $dir_name"
            changes_made=true
        fi
    done
    
    # Check for removed directories
    for dir_name in "${!existing_dirlist[@]}"; do
        local found=false
        for current_dir in "${current_dirs[@]}"; do
            if [[ "$current_dir" == "$dir_name" ]]; then
                found=true
                break
            fi
        done
        
        if [[ "$found" == false ]]; then
            log_info "Removed deleted directory from list: $dir_name"
            changes_made=true
        fi
    done
    
    # Replace the dirlist file
    mv "$temp_dirlist" "$DIRLIST_FILE" || {
        log_error "Failed to update directory list file"
        rm -f "$temp_dirlist"
        return $EXIT_CONFIG_ERROR
    }
    
    if [[ "$changes_made" == true ]]; then
        log_info "Directory list file updated with changes"
    else
        log_info "Directory list file is up to date"
    fi
    
    # Show current dirlist status
    log_info "Current directory list status:"
    while IFS='=' read -r dir_name enabled; do
        if [[ ! "$dir_name" =~ ^#.*$ ]] && [[ -n "$dir_name" ]]; then
            local status_color=""
            local status_text=""
            if [[ "$enabled" == "true" ]]; then
                status_color="$GREEN"
                status_text="ENABLED"
            else
                status_color="$YELLOW"
                status_text="DISABLED"
            fi
            echo -e "  ${status_color}$dir_name: $status_text${NC}"
        fi
    done < "$DIRLIST_FILE"
    
    return $EXIT_SUCCESS
}

#######################################
# Docker Stack Management Functions
#######################################

# Check if a Docker stack is currently running
check_stack_status() {
    local dir_path="$1"
    local dir_name="$2"
    
    log_debug "Checking stack status for: $dir_name at $dir_path"
    
    # Change to the directory to check stack status
    local original_dir
    original_dir="$(pwd)"
    
    if ! cd "$dir_path"; then
        log_error "Cannot change to directory for status check: $dir_path"
        return 1
    fi
    
    # Check if any containers are running for this compose project
    local running_containers
    local ps_output
    ps_output="$(docker compose ps --services --filter "status=running" 2>/dev/null)"
    running_containers=$(echo "$ps_output" | awk 'NF' | wc -l)
    
    log_debug "Docker compose ps output for $dir_name: '$ps_output'"
    log_debug "Running containers count for $dir_name: $running_containers"
    log_debug "Running containers count (hex dump): $(echo -n "$running_containers" | xxd -p)"
    log_debug "Running containers count (with quotes): '$running_containers'"
    log_debug "Length of running_containers: ${#running_containers}"
    
    # Return to original directory
    cd "$original_dir" || {
        log_error "Failed to return to original directory: $original_dir"
        return 1
    }
    
    if [[ "$running_containers" -gt 0 ]]; then
        log_debug "Stack $dir_name is running ($running_containers containers)"
        return 0  # Stack is running
    else
        log_debug "Stack $dir_name is not running (0 containers)"
        return 1  # Stack is not running
    fi
}

# Store the initial state of all stacks before any operations
store_initial_stack_states() {
    log_progress "Checking initial state of all Docker stacks"
    
    local checked_count=0
    local running_count=0
    
    # Check each enabled directory's stack status
    for dir_name in "${!DIRLIST_ARRAY[@]}"; do
        if [[ "${DIRLIST_ARRAY[$dir_name]}" == "true" ]]; then
            local dir_path="$BACKUP_DIR/$dir_name"
            
            if [[ ! -d "$dir_path" ]]; then
                log_warn "Directory not found for state check: $dir_path"
                STACK_INITIAL_STATE["$dir_name"]="not_found"
                continue
            fi
            
            checked_count=$((checked_count + 1))
            
            if check_stack_status "$dir_path" "$dir_name"; then
                STACK_INITIAL_STATE["$dir_name"]="running"
                running_count=$((running_count + 1))
                log_info "Stack $dir_name: initially running"
            else
                STACK_INITIAL_STATE["$dir_name"]="stopped"
                log_info "Stack $dir_name: initially stopped"
            fi
        fi
    done
    
    log_progress "Initial state check completed: $checked_count stacks checked, $running_count running"
    return 0
}

# Smart stop function - only stops stacks that are actually running
smart_stop_stack() {
    local dir_name="$1"
    local dir_path="$2"
    
    # Check if we stored the initial state
    if [[ -z "${STACK_INITIAL_STATE[$dir_name]:-}" ]]; then
        log_warn "No initial state stored for $dir_name, checking current state"
        if check_stack_status "$dir_path" "$dir_name"; then
            STACK_INITIAL_STATE["$dir_name"]="running"
        else
            STACK_INITIAL_STATE["$dir_name"]="stopped"
        fi
    fi
    
    local initial_state="${STACK_INITIAL_STATE[$dir_name]}"
    
    case "$initial_state" in
        "running")
            log_progress "Stopping Docker stack (was running): $dir_name"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would stop running stack: $dir_name"
                return 0
            else
                # Add state validation: check current state before attempting stop
                log_debug "Verifying current state before stopping: $dir_name"
                if ! check_stack_status "$dir_path" "$dir_name"; then
                    log_info "Stack $dir_name is already stopped, skipping stop operation"
                    return 0
                fi
                
                local stop_exit_code=0
                if ! timeout "$DOCKER_TIMEOUT" docker compose stop --timeout "$DOCKER_TIMEOUT"; then
                    stop_exit_code=$?
                fi
                
                # Determine appropriate wait time based on stop result
                local wait_time=2
                if [[ $stop_exit_code -ne 0 ]]; then
                    # Non-zero exit code suggests timeout occurred and SIGKILL was used
                    # Allow more time for SIGKILL to take effect and cleanup to complete
                    wait_time=8
                    log_debug "Stop command timed out (exit code: $stop_exit_code), allowing $wait_time seconds for SIGKILL cleanup"
                else
                    log_debug "Stop command completed gracefully (exit code: $stop_exit_code), allowing $wait_time seconds for final cleanup"
                fi
                
                # Wait for containers to fully shut down
                sleep $wait_time
                
                # Verify stack status with retry logic for robustness
                local verification_attempts=3
                local attempt=1
                local stack_still_running=true
                
                while [[ $attempt -le $verification_attempts ]]; do
                    log_debug "Verifying stack status after stop command for: $dir_name (attempt $attempt/$verification_attempts)"
                    
                    if check_stack_status "$dir_path" "$dir_name"; then
                        if [[ $attempt -lt $verification_attempts ]]; then
                            log_debug "Stack $dir_name still has running containers, waiting 3 more seconds before retry..."
                            sleep 3
                            attempt=$((attempt + 1))
                        else
                            # Final attempt failed
                            stack_still_running=true
                            break
                        fi
                    else
                        # Stack is stopped
                        stack_still_running=false
                        break
                    fi
                done
                
                if [[ $stack_still_running == true ]]; then
                    # Stack is still running after all attempts - this is a real failure
                    log_error "Failed to stop stack: $dir_name (containers still running after stop command and $((verification_attempts * 3 + wait_time)) seconds wait, exit code: $stop_exit_code)"
                    return $EXIT_DOCKER_ERROR
                else
                    # Stack is stopped - success, even if exit code was non-zero
                    if [[ $stop_exit_code -eq 0 ]]; then
                        log_info "Successfully stopped stack: $dir_name (graceful stop)"
                    else
                        log_info "Successfully stopped stack: $dir_name (forced stop after timeout - this is normal for slow containers)"
                    fi
                    return 0
                fi
            fi
            ;;
        "stopped")
            log_info "Skipping stop for stack (was already stopped): $dir_name"
            return 0
            ;;
        "not_found")
            log_warn "Skipping stop for stack (directory not found): $dir_name"
            return 0
            ;;
        *)
            log_warn "Unknown initial state for stack $dir_name: $initial_state, attempting to stop"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would attempt to stop stack: $dir_name"
                return 0
            else
                local stop_exit_code=0
                if ! timeout "$DOCKER_TIMEOUT" docker compose stop --timeout "$DOCKER_TIMEOUT"; then
                    stop_exit_code=$?
                fi
                
                # Determine appropriate wait time based on stop result
                local wait_time=2
                if [[ $stop_exit_code -ne 0 ]]; then
                    # Non-zero exit code suggests timeout occurred and SIGKILL was used
                    # Allow more time for SIGKILL to take effect and cleanup to complete
                    wait_time=8
                    log_debug "Stop command timed out (exit code: $stop_exit_code), allowing $wait_time seconds for SIGKILL cleanup"
                else
                    log_debug "Stop command completed gracefully (exit code: $stop_exit_code), allowing $wait_time seconds for final cleanup"
                fi
                
                # Wait for containers to fully shut down
                sleep $wait_time
                
                # Verify stack status with retry logic for robustness
                local verification_attempts=3
                local attempt=1
                local stack_still_running=true
                
                while [[ $attempt -le $verification_attempts ]]; do
                    log_debug "Verifying stack status after stop command for: $dir_name (attempt $attempt/$verification_attempts)"
                    
                    if check_stack_status "$dir_path" "$dir_name"; then
                        if [[ $attempt -lt $verification_attempts ]]; then
                            log_debug "Stack $dir_name still has running containers, waiting 3 more seconds before retry..."
                            sleep 3
                            attempt=$((attempt + 1))
                        else
                            # Final attempt failed
                            stack_still_running=true
                            break
                        fi
                    else
                        # Stack is stopped
                        stack_still_running=false
                        break
                    fi
                done
                
                if [[ $stack_still_running == true ]]; then
                    # Stack is still running after all attempts - this is a real failure
                    log_error "Failed to stop stack: $dir_name (containers still running after stop command and $((verification_attempts * 3 + wait_time)) seconds wait, exit code: $stop_exit_code)"
                    return $EXIT_DOCKER_ERROR
                else
                    # Stack is stopped - success, even if exit code was non-zero
                    if [[ $stop_exit_code -eq 0 ]]; then
                        log_info "Successfully stopped stack: $dir_name (graceful stop)"
                    else
                        log_info "Successfully stopped stack: $dir_name (forced stop after timeout - this is normal for slow containers)"
                    fi
                    return 0
                fi
            fi
            ;;
    esac
}

# Smart start function - only starts stacks that were originally running
smart_start_stack() {
    local dir_name="$1"
    local dir_path="$2"
    
    local initial_state="${STACK_INITIAL_STATE[$dir_name]:-unknown}"
    
    case "$initial_state" in
        "running")
            log_progress "Restarting Docker stack (was originally running): $dir_name"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would restart originally running stack: $dir_name"
                return 0
            else
                if timeout "$DOCKER_TIMEOUT" docker compose start; then
                    log_info "Successfully restarted stack: $dir_name"
                    return 0
                else
                    local exit_code=$?
                    log_error "Failed to restart stack: $dir_name (exit code: $exit_code)"
                    return $EXIT_DOCKER_ERROR
                fi
            fi
            ;;
        "stopped")
            log_info "Skipping restart for stack (was originally stopped): $dir_name"
            return 0
            ;;
        "not_found")
            log_warn "Skipping restart for stack (directory not found): $dir_name"
            return 0
            ;;
        *)
            log_warn "Unknown initial state for stack $dir_name: $initial_state, skipping restart"
            return 0
            ;;
    esac
}

#######################################
# Sequential Processing Functions
#######################################

# Process a single directory (smart stop → backup → smart start)
process_directory() {
    local dir_name="$1"
    local dir_path="$BACKUP_DIR/$dir_name"
    
    log_progress "Processing directory: $dir_name"
    log_debug "Directory path: $dir_path"
    log_debug "Current working directory: $(pwd)"
    log_debug "Initial state for $dir_name: ${STACK_INITIAL_STATE[$dir_name]:-unknown}"
    
    # Validate directory exists
    if [[ ! -d "$dir_path" ]]; then
        log_error "Directory not found: $dir_path"
        return $EXIT_VALIDATION_ERROR
    fi
    log_debug "Directory exists: $dir_path"
    
    # Change to directory
    log_debug "Attempting to change to directory: $dir_path"
    if ! cd "$dir_path"; then
        log_error "Cannot change to directory: $dir_path"
        return $EXIT_DOCKER_ERROR
    fi
    log_debug "Successfully changed to directory: $(pwd)"
    
    # Step 1: Smart stop Docker stack (only if it was running)
    if ! smart_stop_stack "$dir_name" "$dir_path"; then
        log_error "Failed to stop stack: $dir_name"
        return $EXIT_DOCKER_ERROR
    fi
    
    # Step 2: Backup directory (with performance optimization if enabled)
    log_progress "Backing up directory: $dir_name"
    
    # Use optimized backup if performance mode is enabled
    local backup_function="backup_single_directory"
    if [[ "$ENABLE_PERFORMANCE_MODE" == "true" ]]; then
        backup_function="backup_single_directory_optimized"
        log_debug "Using performance-optimized backup for: $dir_name"
    fi
    
    if ! "$backup_function" "$dir_name" "$dir_path"; then
        log_error "Backup failed for directory: $dir_name"
        # Try to restart stack even if backup failed (only if it was originally running)
        log_progress "Attempting to restart stack after backup failure: $dir_name"
        smart_start_stack "$dir_name" "$dir_path" || log_error "Failed to restart stack after backup failure: $dir_name"
        return $EXIT_BACKUP_ERROR
    fi
    
    # Step 2.1: Verify backup if enabled
    if ! verify_backup "$dir_name"; then
        log_error "Backup verification failed for directory: $dir_name"
        # Continue with stack restart even if verification fails
        log_warn "Continuing despite verification failure"
    fi
    
    # Step 2.5: Apply retention policy if configured
    if ! apply_retention_policy "$dir_name"; then
        log_warn "Retention policy failed for directory: $dir_name (continuing with stack restart)"
        # Don't fail the entire process if retention policy fails
    fi
    
    # Step 3: Smart start Docker stack (only if it was originally running)
    if ! smart_start_stack "$dir_name" "$dir_path"; then
        log_error "Failed to restart stack: $dir_name"
        return $EXIT_DOCKER_ERROR
    fi
    
    # Return to script directory for next iteration
    log_debug "Returning to script directory: $SCRIPT_DIR"
    if ! cd "$SCRIPT_DIR"; then
        log_error "Failed to return to script directory: $SCRIPT_DIR"
        return $EXIT_DOCKER_ERROR
    fi
    log_debug "Successfully returned to: $(pwd)"
    
    log_info "Successfully processed directory: $dir_name"
    return $EXIT_SUCCESS
}

# Backup a single directory using restic
backup_single_directory() {
    local dir_name="$1"
    local dir_path="$2"
    
    log_info "Starting restic backup for: $dir_name"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would backup directory: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    # Ensure restic environment variables are exported
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD
    
    local backup_start_time
    backup_start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Create backup with timeout, showing restic output
    local backup_cmd=(
        timeout "$BACKUP_TIMEOUT"
        restic backup
        --verbose
        --tag "docker-backup"
        --tag "selective-backup"
        --tag "$dir_name"
        --tag "$(date '+%Y-%m-%d')"
    )
    
    # Add hostname parameter if configured
    if [[ -n "$HOSTNAME" ]]; then
        backup_cmd+=(--hostname "$HOSTNAME")
        log_debug "Using custom hostname for backup: $HOSTNAME"
    else
        log_debug "Using system default hostname for backup"
    fi
    
    # Add the directory path as the final argument
    backup_cmd+=("$dir_path")
    
    log_info "Executing backup command for $dir_name"
    log_debug "Backup command: ${backup_cmd[*]}"
    log_progress "Starting restic backup - output will be displayed below:"
    
    # Run restic with output visible to user and logged to file
    # Use a more robust approach to capture exit status while showing output
    local restic_output_file
    restic_output_file="$(mktemp)"
    
    # Run restic command with real-time output display and logging
    if "${backup_cmd[@]}" 2>&1 | tee "$restic_output_file"; then
        # Also append the output to our log file with proper formatting
        while IFS= read -r line; do
            log_message "RESTIC" "$line"
        done < "$restic_output_file"
        rm -f "$restic_output_file"
        local backup_end_time
        backup_end_time="$(date '+%Y-%m-%d %H:%M:%S')"
        log_info "Backup completed successfully for: $dir_name"
        log_debug "Backup start time: $backup_start_time"
        log_debug "Backup end time: $backup_end_time"
        return $EXIT_SUCCESS
    else
        local exit_code=$?
        # Also append the output to our log file with proper formatting
        while IFS= read -r line; do
            log_message "RESTIC" "$line"
        done < "$restic_output_file"
        rm -f "$restic_output_file"
        log_error "Backup failed for $dir_name with exit code: $exit_code"
        return $EXIT_BACKUP_ERROR
    fi
}

# Apply retention policy and auto-prune if configured
apply_retention_policy() {
    local dir_name="$1"
    
    # Only proceed if AUTO_PRUNE is enabled
    if [[ "$AUTO_PRUNE" != "true" ]]; then
        log_debug "Auto-prune disabled, skipping retention policy for: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    log_info "Applying retention policy for: $dir_name"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would apply retention policy for: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    # Ensure restic environment variables are exported
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD
    
    # Build forget command with retention policy
    local forget_cmd=(restic forget --verbose)
    
    # Add hostname parameter if configured (to match backup hostname)
    if [[ -n "$HOSTNAME" ]]; then
        forget_cmd+=(--hostname "$HOSTNAME")
        log_debug "Using custom hostname for retention policy: $HOSTNAME"
    fi
    
    # Add tag filter to only affect backups for this directory
    forget_cmd+=(--tag "$dir_name")
    
    # Add retention policy parameters if configured
    local retention_params_added=false
    
    if [[ -n "$KEEP_DAILY" ]] && [[ "$KEEP_DAILY" =~ ^[0-9]+$ ]]; then
        forget_cmd+=(--keep-daily "$KEEP_DAILY")
        retention_params_added=true
        log_debug "Added retention policy: keep-daily=$KEEP_DAILY"
    fi
    
    if [[ -n "$KEEP_WEEKLY" ]] && [[ "$KEEP_WEEKLY" =~ ^[0-9]+$ ]]; then
        forget_cmd+=(--keep-weekly "$KEEP_WEEKLY")
        retention_params_added=true
        log_debug "Added retention policy: keep-weekly=$KEEP_WEEKLY"
    fi
    
    if [[ -n "$KEEP_MONTHLY" ]] && [[ "$KEEP_MONTHLY" =~ ^[0-9]+$ ]]; then
        forget_cmd+=(--keep-monthly "$KEEP_MONTHLY")
        retention_params_added=true
        log_debug "Added retention policy: keep-monthly=$KEEP_MONTHLY"
    fi
    
    if [[ -n "$KEEP_YEARLY" ]] && [[ "$KEEP_YEARLY" =~ ^[0-9]+$ ]]; then
        forget_cmd+=(--keep-yearly "$KEEP_YEARLY")
        retention_params_added=true
        log_debug "Added retention policy: keep-yearly=$KEEP_YEARLY"
    fi
    
    # Only proceed if at least one retention parameter was configured
    if [[ "$retention_params_added" != "true" ]]; then
        log_warn "No valid retention policy parameters configured, skipping forget operation for: $dir_name"
        return $EXIT_SUCCESS
    fi
    
    # Add --prune flag to actually remove data
    forget_cmd+=(--prune)
    
    log_info "Executing retention policy command for $dir_name"
    log_debug "Retention command: ${forget_cmd[*]}"
    log_progress "Applying retention policy - output will be displayed below:"
    
    # Run restic forget command with output visible to user and logged to file
    local restic_output_file
    restic_output_file="$(mktemp)"
    
    # Run restic command with real-time output display and logging
    if "${forget_cmd[@]}" 2>&1 | tee "$restic_output_file"; then
        # Also append the output to our log file with proper formatting
        while IFS= read -r line; do
            log_message "RESTIC" "$line"
        done < "$restic_output_file"
        rm -f "$restic_output_file"
        log_info "Retention policy applied successfully for: $dir_name"
        return $EXIT_SUCCESS
    else
        local exit_code=$?
        # Also append the output to our log file with proper formatting
        while IFS= read -r line; do
            log_message "RESTIC" "$line"
        done < "$restic_output_file"
        rm -f "$restic_output_file"
        log_error "Retention policy failed for $dir_name with exit code: $exit_code"
        return $EXIT_BACKUP_ERROR
    fi
}

#######################################
# Restic Management
#######################################

# Check if restic is available and configured
check_restic() {
    log_info "Checking restic availability and configuration"
    
    if ! command -v restic >/dev/null 2>&1; then
        log_error "restic command not found. Please install restic."
        return $EXIT_BACKUP_ERROR
    fi
    
    # Use config file values first, then check environment variables as fallback
    local repo="$RESTIC_REPOSITORY"
    
    # Check environment variables as fallback if config values are empty
    if [[ -z "$repo" ]]; then
        repo="$(printenv RESTIC_REPOSITORY || true)"
        if [[ -n "$repo" ]]; then
            log_info "Using RESTIC_REPOSITORY from environment variable (fallback)"
            RESTIC_REPOSITORY="$repo"
        fi
    fi
    
    if [[ -z "$repo" ]]; then
        log_error "RESTIC_REPOSITORY not configured in config file or environment variables"
        return $EXIT_BACKUP_ERROR
    fi
    
    # Export repository
    export RESTIC_REPOSITORY="$repo"
    
    # Setup password authentication using enhanced method
    if ! setup_restic_password; then
        log_error "Failed to setup restic password authentication"
        return $EXIT_BACKUP_ERROR
    fi
    
    # Test restic repository access
    if ! restic snapshots --quiet >/dev/null 2>&1; then
        log_error "Cannot access restic repository. Please check configuration."
        return $EXIT_BACKUP_ERROR
    fi
    
    log_info "restic is available and configured"
    return $EXIT_SUCCESS
}

#######################################
# PID File Management
#######################################

# Create PID file to prevent concurrent runs
create_pid_file() {
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid
        existing_pid="$(cat "$PID_FILE" 2>/dev/null || echo "")"
        
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log_error "Another instance is already running (PID: $existing_pid)"
            return $EXIT_CONFIG_ERROR
        else
            log_warn "Stale PID file found, removing it"
            rm -f "$PID_FILE"
        fi
    fi
    
    echo $$ > "$PID_FILE" || {
        log_error "Cannot create PID file: $PID_FILE"
        return $EXIT_CONFIG_ERROR
    }
    
    log_debug "Created PID file: $PID_FILE (PID: $$)"
    return $EXIT_SUCCESS
}

#######################################
# Main Execution Flow
#######################################

# Display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Docker Stack Selective Sequential Backup Script

This script implements a two-phase selective backup approach:
1. Scan Phase: Discovers directories and manages .dirlist file
2. Sequential Backup Phase: Processes only enabled directories one at a time

OPTIONS:
    -v, --verbose          Enable verbose output
    -n, --dry-run         Perform a dry run without making changes
    -h, --help            Display this help message
    --list-backups        List recent backup snapshots
    --restore-preview DIR Preview restore for directory
    --generate-config     Generate configuration template
    --validate-config     Validate configuration file
    --health-check        Generate health check report

CONFIGURATION:
    Configuration is read from: $CONFIG_FILE (in script directory)
    Required: BACKUP_DIR=/path/to/backup/directory
    Required: RESTIC_REPOSITORY=/path/to/restic/repository
    Required: RESTIC_PASSWORD=your-restic-password (or use password file/command)
    Optional: BACKUP_TIMEOUT=3600, DOCKER_TIMEOUT=30
    Optional: HOSTNAME=custom-hostname (defaults to system hostname)
    Optional: KEEP_DAILY=7, KEEP_WEEKLY=4, KEEP_MONTHLY=12, KEEP_YEARLY=3
    Optional: AUTO_PRUNE=true (enables automatic pruning with retention policy)
    
    Phase 1 Security & Verification Features:
    Optional: ENABLE_PASSWORD_FILE=true, RESTIC_PASSWORD_FILE=/path/to/file
    Optional: ENABLE_PASSWORD_COMMAND=true, RESTIC_PASSWORD_COMMAND="command"
    Optional: ENABLE_BACKUP_VERIFICATION=true, VERIFICATION_DEPTH=files
    Optional: MIN_DISK_SPACE_MB=1024 (minimum free space required)
    
    Phase 2 Performance & Resource Monitoring Features:
    Optional: ENABLE_PERFORMANCE_MODE=true (restic optimization flags)
    Optional: ENABLE_DOCKER_STATE_CACHE=true (reduces Docker API calls)
    Optional: CHECK_SYSTEM_RESOURCES=true (monitors memory/load)
    Optional: MEMORY_THRESHOLD_MB=512, LOAD_THRESHOLD=80 (resource limits)
    Optional: ENABLE_PARALLEL_PROCESSING=true, MAX_PARALLEL_JOBS=2

DIRECTORY SELECTION:
    Edit the generated .dirlist file to control which directories are backed up:
    - true = backup enabled
    - false = skip backup (default for new directories)

EXAMPLES:
    $SCRIPT_NAME                    # Run selective backup
    $SCRIPT_NAME --verbose          # Run with verbose output
    $SCRIPT_NAME --dry-run          # Test run without making changes

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Validation error
    3 - Backup error
    4 - Docker error
    5 - Signal/interruption error

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit $EXIT_SUCCESS
                ;;
            --list-backups)
                # Initialize logging and load config for this command
                init_logging
                load_config || exit $?
                list_backups
                exit $?
                ;;
            --restore-preview)
                if [[ -z "$2" ]]; then
                    log_error "--restore-preview requires a directory name"
                    exit $EXIT_CONFIG_ERROR
                fi
                # Initialize logging and load config for this command
                init_logging
                load_config || exit $?
                restore_preview "$2"
                exit $?
                ;;
            --generate-config)
                # Initialize logging for this command
                init_logging
                generate_config_template
                exit $?
                ;;
            --validate-config)
                # Initialize logging and load config for validation
                init_logging
                load_config || exit $?
                validate_configuration
                exit $?
                ;;
            --health-check)
                # Initialize logging and load config for health check
                init_logging
                load_config || exit $?
                generate_health_report
                if [[ $? -eq 0 ]]; then
                    log_info "Health check report generated: $SCRIPT_DIR/logs/backup_health.json"
                fi
                exit $?
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
    
    log_info "=== Docker Stack Selective Sequential Backup Started ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Start time: $start_time"
    log_info "Verbose: $VERBOSE"
    log_info "Dry run: $DRY_RUN"
    
    # Load and validate configuration
    load_config || exit $?
    validate_configuration || exit $?
    
    # Send backup started notification
    send_notification "backup_started" "Docker backup process initiated"
    
    # Phase 1: Enhanced pre-flight checks
    log_progress "=== Phase 1: Pre-flight Security and Health Checks ==="
    
    # Check file permissions for config file
    check_file_permissions "$CONFIG_FILE" "600" || log_warn "Config file permissions should be more restrictive"
    
    # Check disk space
    if ! check_disk_space "$BACKUP_DIR"; then
        log_error "Insufficient disk space for backup operations"
        exit $EXIT_VALIDATION_ERROR
    fi
    
    # Check prerequisites
    check_restic || exit $?
    
    # Repository health check
    if ! check_repository_health; then
        log_error "Repository health check failed"
        exit $EXIT_BACKUP_ERROR
    fi
    
    # Phase 2: System resource monitoring
    check_system_resources
    
    # Phase 3: Initialize enhanced monitoring
    initialize_metrics
    generate_status_report "starting" "Backup session initiated"
    
    # Phase 2: Scan directories and update .dirlist
    log_progress "=== PHASE 2: Directory Scanning ==="
    scan_directories || exit $?
    
    # Phase 3: Sequential backup processing
    log_progress "=== PHASE 3: Sequential Backup Processing ==="
    
    # Load directory list
    if ! load_dirlist; then
        log_error "Failed to load directory list. Run scan phase first."
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Debug: Show loaded dirlist
    log_progress "Loaded ${#DIRLIST_ARRAY[@]} directories from dirlist file"
    
    # Debug: Validate array is properly populated
    if [[ ${#DIRLIST_ARRAY[@]} -eq 0 ]]; then
        log_error "Directory list is empty after loading"
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Debug: Show array contents before iteration
    log_debug "Dirlist array contents:"
    for key in "${!DIRLIST_ARRAY[@]}"; do
        log_debug "  $key=${DIRLIST_ARRAY[$key]}"
    done
    
    # Phase 2: Initialize Docker state caching if enabled
    initialize_docker_cache
    
    # Store initial state of all Docker stacks before any operations
    store_initial_stack_states || exit $?
    
    # Count enabled directories
    local enabled_count=0
    local processed_count=0
    local failed_count=0
    
    log_debug "Starting directory counting loop..."
    for dir_name in "${!DIRLIST_ARRAY[@]}"; do
        log_debug "Processing directory: $dir_name with value: ${DIRLIST_ARRAY[$dir_name]}"
        if [[ "${DIRLIST_ARRAY[$dir_name]}" == "true" ]]; then
            enabled_count=$((enabled_count + 1))
            log_progress "Found enabled directory: $dir_name"
            log_debug "Enabled count is now: $enabled_count"
        fi
    done
    log_debug "Directory counting loop completed successfully"
    
    log_progress "Total enabled directories: $enabled_count"
    
    if [[ $enabled_count -eq 0 ]]; then
        log_warn "No directories enabled for backup in .dirlist file"
        log_info "Edit $DIRLIST_FILE to enable directories for backup"
        log_info "To enable a directory, change 'false' to 'true' for the desired directories"
        log_info "Then run the script again to perform the backup"
        
        # Show completion message for scan-only run
        local end_time
        end_time="$(date '+%Y-%m-%d %H:%M:%S')"
        log_progress "=== Directory Scan Completed ==="
        log_progress "Start time: $start_time"
        log_progress "End time: $end_time"
        log_progress "Directories discovered: ${#DIRLIST_ARRAY[@]}"
        log_progress "Directories enabled: $enabled_count"
        exit $EXIT_SUCCESS
    else
        log_progress "Processing $enabled_count enabled directories sequentially"
        
        # Show summary of initial stack states
        log_progress "=== Initial Stack States Summary ==="
        local running_stacks=0
        local stopped_stacks=0
        for dir_name in "${!DIRLIST_ARRAY[@]}"; do
            if [[ "${DIRLIST_ARRAY[$dir_name]}" == "true" ]]; then
                local state="${STACK_INITIAL_STATE[$dir_name]:-unknown}"
                case "$state" in
                    "running")
                        running_stacks=$((running_stacks + 1))
                        log_info "  $dir_name: RUNNING (will be stopped and restarted)"
                        ;;
                    "stopped")
                        stopped_stacks=$((stopped_stacks + 1))
                        log_info "  $dir_name: STOPPED (will remain stopped)"
                        ;;
                    *)
                        log_warn "  $dir_name: $state"
                        ;;
                esac
            fi
        done
        log_progress "Stacks to stop/restart: $running_stacks, Stacks to leave stopped: $stopped_stacks"
        
        # Track the first failure exit code to return the appropriate error type
        local first_failure_exit_code=0
        
        # Process each enabled directory with progress tracking
        for dir_name in "${!DIRLIST_ARRAY[@]}"; do
            if [[ "${DIRLIST_ARRAY[$dir_name]}" == "true" ]]; then
                processed_count=$((processed_count + 1))
                
                # Update progress bar
                show_progress "$processed_count" "$enabled_count" "Processing directories"
                
                log_progress "Processing directory $processed_count of $enabled_count: $dir_name"
                log_debug "About to call process_directory for: $dir_name"
                
                # JSON logging for directory start
                log_json "directory_start" "$dir_name" "processing" "Starting backup process"
                collect_metric "directory_start" "$(date +%s)" "$dir_name"
                
                local dir_start_time
                dir_start_time="$(date +%s)"
                
                if process_directory "$dir_name"; then
                    local dir_end_time
                    dir_end_time="$(date +%s)"
                    local dir_duration=$((dir_end_time - dir_start_time))
                    
                    log_info "Successfully completed processing: $dir_name"
                    log_json "directory_complete" "$dir_name" "success" "Backup completed in ${dir_duration}s"
                    collect_metric "directory_duration" "$dir_duration" "$dir_name"
                    collect_metric "directory_success" "1" "$dir_name"
                else
                    local exit_code=$?
                    local dir_end_time
                    dir_end_time="$(date +%s)"
                    local dir_duration=$((dir_end_time - dir_start_time))
                    
                    log_error "Failed to process directory: $dir_name (exit code: $exit_code)"
                    log_json "directory_error" "$dir_name" "failed" "Backup failed with exit code $exit_code after ${dir_duration}s"
                    collect_metric "directory_duration" "$dir_duration" "$dir_name"
                    collect_metric "directory_error" "$exit_code" "$dir_name"
                    
                    failed_count=$((failed_count + 1))
                    
                    # Preserve the first failure exit code to return the appropriate error type
                    if [[ $first_failure_exit_code -eq 0 ]]; then
                        first_failure_exit_code=$exit_code
                    fi
                fi
            fi
        done
    fi
    
    local end_time
    end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    log_progress "=== Docker Stack Selective Sequential Backup Completed ==="
    log_progress "Start time: $start_time"
    log_progress "End time: $end_time"
    log_progress "Directories enabled: $enabled_count"
    log_progress "Directories processed: $processed_count"
    log_progress "Directories failed: $failed_count"
    
    # Generate health report
    generate_health_report
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Some directories failed to process. Check logs for details."
        send_notification "backup_completed" "Backup completed with issues" "failed: $failed_count of $enabled_count"
        exit $first_failure_exit_code
    fi
    
    send_notification "backup_completed" "Backup completed successfully" "success"
    exit $EXIT_SUCCESS
}

#######################################
# Script Entry Point
#######################################

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for help option first (before logging initialization)
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            usage
            exit $EXIT_SUCCESS
        fi
    done
    
    # Initialize logging
    init_logging
    
    # Set up signal handlers
    setup_signal_handlers
    
    # Create PID file
    create_pid_file || exit $?
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main function
    main
fi