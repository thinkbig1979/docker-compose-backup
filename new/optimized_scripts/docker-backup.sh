
#!/bin/bash

# Docker Stack Selective Sequential Backup Script - OPTIMIZED VERSION
# Selective backup solution for Docker compose stacks using restic
# Author: Generated for production use
# Version: 3.0 - Optimized with critical fixes and reliability improvements

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/backup.conf}"

# Configuration-driven paths (externalized from hardcoded values)
LOG_DIR=""
LOG_FILE=""
PID_FILE=""
DIRLIST_FILE=""

# Default configuration
DEFAULT_BACKUP_TIMEOUT=3600
DEFAULT_DOCKER_TIMEOUT=30
DEFAULT_LOG_DIR="$SCRIPT_DIR/logs"
DEFAULT_DIRLIST_FILE="$SCRIPT_DIR/dirlist"

# Global variables
BACKUP_DIR=""
BACKUP_TIMEOUT="${DEFAULT_BACKUP_TIMEOUT}"
DOCKER_TIMEOUT="${DEFAULT_DOCKER_TIMEOUT}"
RESTIC_REPOSITORY=""
RESTIC_PASSWORD=""
HOSTNAME=""
KEEP_DAILY=""
KEEP_WEEKLY=""
KEEP_MONTHLY=""
KEEP_YEARLY=""
AUTO_PRUNE=""
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

####
# Logging Functions
####

# Initialize logging with configurable paths
init_logging() {
    # Set log directory from config or use default
    LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
    LOG_FILE="$LOG_DIR/docker_backup.log"
    PID_FILE="$LOG_DIR/docker_backup.pid"
    
    # Ensure log directory exists
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" || {
            echo "ERROR: Cannot create log directory: $LOG_DIR" >&2
            exit $EXIT_CONFIG_ERROR
        }
    fi
    
    # Ensure log file is writable
    if [[ ! -w "$LOG_FILE" ]] && [[ ! -w "$LOG_DIR" ]]; then
        echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot create log file: $LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    }
    
    # Implement basic log rotation (keep last 10MB)
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        touch "$LOG_FILE"
    fi
}

# Enhanced log message with timestamp and severity
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Sanitize message to prevent credential exposure
    local sanitized_message
    sanitized_message="$(echo "$message" | sed 's/RESTIC_PASSWORD=[^[:space:]]*/RESTIC_PASSWORD=[REDACTED]/g')"
    
    # Write to log file
    echo "[$timestamp] [$level] $sanitized_message" >> "$LOG_FILE"
    
    # Also output to console if verbose, error/warning, progress, or restic output
    if [[ "$VERBOSE" == true ]] || [[ "$level" =~ ^(ERROR|WARN|PROGRESS|RESTIC)$ ]]; then
        case "$level" in
            ERROR)
                echo -e "${RED}[$timestamp] [ERROR] $sanitized_message${NC}" >&2
                ;;
            WARN)
                echo -e "${YELLOW}[$timestamp] [WARN] $sanitized_message${NC}" >&2
                ;;
            INFO)
                echo -e "${GREEN}[$timestamp] [INFO] $sanitized_message${NC}"
                ;;
            DEBUG)
                echo -e "${BLUE}[$timestamp] [DEBUG] $sanitized_message${NC}"
                ;;
            PROGRESS)
                echo -e "${CYAN}[$timestamp] [PROGRESS] $sanitized_message${NC}"
                ;;
            RESTIC)
                echo -e "${CYAN}$sanitized_message${NC}"
                ;;
            *)
                echo "[$timestamp] [$level] $sanitized_message"
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

####
# Signal Handling
####

# Enhanced cleanup function for graceful shutdown
cleanup() {
    local exit_code=$?
    log_info "Cleanup initiated (exit code: $exit_code)"
    
    # Remove PID file
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE" 2>/dev/null || true
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

####
# Configuration Management
####

# Enhanced configuration loading with validation
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
            LOG_DIR)
                LOG_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
            DIRLIST_FILE)
                DIRLIST_FILE="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
                ;;
        esac
    done <<< "$config_content"
    
    # Set defaults for optional paths
    DIRLIST_FILE="${DIRLIST_FILE:-$DEFAULT_DIRLIST_FILE}"
    
    log_info "Configuration loaded successfully"
    return $EXIT_SUCCESS
}

# Enhanced configuration validation
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
    
    if [[ -z "$RESTIC_PASSWORD" ]]; then
        log_error "RESTIC_PASSWORD not specified in configuration"
        return $EXIT_CONFIG_ERROR
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
    log_debug "LOG_DIR: ${LOG_DIR:-[DEFAULT]}"
    log_debug "DIRLIST_FILE: ${DIRLIST_FILE:-[DEFAULT]}"
    
    return $EXIT_SUCCESS
}

####
# Container Management Functions - CRITICAL FIXES APPLIED
####

# Enhanced container health verification
wait_for_containers_stopped() {
    local dir_name="$1"
    local max_wait="${2:-10}"
    local attempt=1
    
    log_debug "Waiting for containers to stop: $dir_name (max wait: ${max_wait}s)"
    
    while [[ $attempt -le $max_wait ]]; do
        local running_containers
        running_containers="$(docker compose ps --services --filter "status=running" 2>/dev/null | awk 'NF' | wc -l)"
        
        if [[ "$running_containers" -eq 0 ]]; then
            log_debug "All containers stopped for: $dir_name (after ${attempt}s)"
            return 0
        fi
        
        log_debug "Still waiting for containers to stop: $dir_name ($running_containers running, attempt $attempt/$max_wait)"
        sleep 1
        ((attempt++))
    done
    
    log_warn "Timeout waiting for containers to stop: $dir_name"
    return 1
}

# Enhanced container health verification
wait_for_containers_healthy() {
    local dir_name="$1"
    local max_wait="${2:-30}"
    local attempt=1
    
    log_debug "Waiting for containers to become healthy: $dir_name (max wait: ${max_wait}s)"
    
    while [[ $attempt -le $max_wait ]]; do
        local unhealthy_containers
        unhealthy_containers="$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)"
        
        if [[ "$unhealthy_containers" -gt 0 ]]; then
            # Basic health check - containers are running
            log_debug "Containers are running for: $dir_name (after ${attempt}s)"
            return 0
        fi
        
        log_debug "Still waiting for containers to start: $dir_name (attempt $attempt/$max_wait)"
        sleep 1
        ((attempt++))
    done
    
    log_warn "Timeout waiting for containers to become healthy: $dir_name"
    return 1
}

# CRITICAL FIX: Enhanced container stop with single timeout
stop_containers_safely() {
    local dir_name="$1"
    local dir_path="$2"
    
    log_debug "Attempting safe container stop for: $dir_name"
    
    # FIXED: Use single timeout instead of nested timeouts
    if docker compose stop --timeout "$DOCKER_TIMEOUT"; then
        log_debug "Graceful stop command completed for: $dir_name"
        
        # Verify containers actually stopped
        if wait_for_containers_stopped "$dir_name" 10; then
            log_info "Successfully stopped containers: $dir_name"
            return 0
        else
            log_warn "Containers did not stop gracefully, attempting force stop: $dir_name"
        fi
    else
        log_warn "Graceful stop failed, attempting force stop: $dir_name"
    fi
    
    # Force stop if graceful failed
    if docker compose kill; then
        if wait_for_containers_stopped "$dir_name" 5; then
            log_info "Successfully force-stopped containers: $dir_name"
            return 0
        fi
    fi
    
    log_error "Failed to stop containers: $dir_name"
    return 1
}

# CRITICAL FIX: Enhanced container start with health verification
start_containers_safely() {
    local dir_name="$1"
    local dir_path="$2"
    
    log_debug "Attempting safe container start for: $dir_name"
    
    if docker compose start; then
        # Wait for containers to become healthy
        if wait_for_containers_healthy "$dir_name" "$DOCKER_TIMEOUT"; then
            log_info "Successfully started and verified containers: $dir_name"
            return 0
        else
            log_error "Containers started but failed health verification: $dir_name"
            return 1
        fi
    else
        log_error "Failed to start containers: $dir_name"
        return 1
    fi
}

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
    
    log_debug "Running containers count for $dir_name: $running_containers"
    
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

# CRITICAL FIX: Enhanced smart stop function with improved error handling
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
                # Verify current state before attempting stop
                if ! check_stack_status "$dir_path" "$dir_name"; then
                    log_info "Stack $dir_name is already stopped, skipping stop operation"
                    return 0
                fi
                
                # Use enhanced stop function with single timeout
                if stop_containers_safely "$dir_name" "$dir_path"; then
                    return 0
                else
                    log_error "Failed to stop stack: $dir_name"
                    return $EXIT_DOCKER_ERROR
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
                if stop_containers_safely "$dir_name" "$dir_path"; then
                    return 0
                else
                    log_error "Failed to stop stack: $dir_name"
                    return $EXIT_DOCKER_ERROR
                fi
            fi
            ;;
    esac
}

# CRITICAL FIX: Enhanced smart start function with health verification
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
                if start_containers_safely "$dir_name" "$dir_path"; then
                    return 0
                else
                    log_error "Failed to restart stack: $dir_name"
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

####
# Directory List Management
####

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
            DIRLIST_ARRAY["$dir_name"]="$enabled"
            ((loaded_count++))
        else
            log_warn "Invalid format in dirlist: $dir_name=$enabled"
        fi
    done < "$DIRLIST_FILE"
    
    log_debug "Load completed. Total entries loaded: $loaded_count"
    
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

####
# Sequential Processing Functions
####

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
    
    # Step 2: Backup directory
    log_progress "Backing up directory: $dir_name"
    if ! backup_single_directory "$dir_name" "$dir_path"; then
        log_error "Backup failed for directory: $dir_name"
        # Try to restart stack even if backup failed (only if it was originally running)
        log_progress "Attempting to restart stack after backup failure: $dir_name"
        smart_start_stack "$dir_name" "$dir_path" || log_error "Failed to restart stack after backup failure: $dir_name"
        return $EXIT_BACKUP_ERROR
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
        backup_cmd+=(--host "$HOSTNAME")
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
        forget_cmd+=(--host "$HOSTNAME")
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

####
# Restic Management
####

# Check if restic is available and configured
check_restic() {
    log_info "Checking restic availability and configuration"
    
    if ! command -v restic >/dev/null 2>&1; then
        log_error "restic command not found. Please install restic."
        return $EXIT_BACKUP_ERROR
    fi
    
    # Use config file values first, then check environment variables as fallback
    local repo="$RESTIC_REPOSITORY"
    local password="$RESTIC_PASSWORD"
    
    # Check environment variables as fallback if config values are empty
    if [[ -z "$repo" ]]; then
        repo="$(printenv RESTIC_REPOSITORY || true)"
        if [[ -n "$repo" ]]; then
            log_info "Using RESTIC_REPOSITORY from environment variable (fallback)"
        fi
    fi
    if [[ -z "$password" ]]; then
        password="$(printenv RESTIC_PASSWORD || true)"
        if [[ -n "$password" ]]; then
            log_info "Using RESTIC_PASSWORD from environment variable (fallback)"
        fi
    fi
    
    if [[ -z "$repo" ]]; then
        log_error "RESTIC_REPOSITORY not configured in config file or environment variables"
        return $EXIT_BACKUP_ERROR
    fi
    
    if [[ -z "$password" ]]; then
        log_error "RESTIC_PASSWORD not configured in config file or environment variables"
        return $EXIT_BACKUP_ERROR
    fi
    
    # Export variables for restic commands
    export RESTIC_REPOSITORY="$repo"
    export RESTIC_PASSWORD="$password"
    
    # Test restic repository access
    if ! restic snapshots --quiet >/dev/null 2>&1; then
        log_error "Cannot access restic repository. Please check configuration."
        return $EXIT_BACKUP_ERROR
    fi
    
    log_info "restic is available and configured"
    return $EXIT_SUCCESS
}

####
# PID File Management
####

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

####
# Main Execution Flow
####

# Display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Docker Stack Selective Sequential Backup Script - OPTIMIZED VERSION

This script implements a two-phase selective backup approach:
1. Scan Phase: Discovers directories and manages .dirlist file
2. Sequential Backup Phase: Processes only enabled directories one at a time

CRITICAL FIXES APPLIED:
- Fixed double timeout issue in container management
- Enhanced container stop/start verification logic
- Improved error handling and recovery
- Externalized hardcoded configuration values
- Added comprehensive logging with credential sanitization

OPTIONS:
    -v, --verbose    Enable verbose output
    -n, --dry-run    Perform a dry run without making changes
    -h, --help       Display this help message

CONFIGURATION:
    Configuration is read from: $CONFIG_FILE (in script directory)
    Required: BACKUP_DIR=/path/to/backup/directory
    Required: RESTIC_REPOSITORY=/path/to/restic/repository
    Required: RESTIC_PASSWORD=your-restic-password
    Optional: BACKUP_TIMEOUT=3600, DOCKER_TIMEOUT=30
    Optional: HOSTNAME=custom-hostname (defaults to system hostname)
    Optional: KEEP_DAILY=7, KEEP_WEEKLY=4, KEEP_MONTHLY=12, KEEP_YEARLY=3
    Optional: AUTO_PRUNE=true (enables automatic pruning with retention policy)
    Optional: LOG_DIR=/custom/log/path (defaults to script_dir/logs)
    Optional: DIRLIST_FILE=/custom/dirlist/path (defaults to script_dir/dirlist)

DIRECTORY SELECTION:
    Edit the generated .dirlist file to control which directories are backed up:
    - true = backup enabled
    - false = skip backup (default for new directories)

EXAMPLES:
    $SCRIPT_NAME                # Run selective backup
    $SCRIPT_NAME --verbose      # Run with verbose output
    $SCRIPT_NAME --dry-run      # Test run without making changes

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
    
    log_info "=== Docker Stack Selective Sequential Backup Started (OPTIMIZED) ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Start time: $start_time"
    log_info "Verbose: $VERBOSE"
    log_info "Dry run: $DRY_RUN"
    
    # Load and validate configuration
    load_config || exit $?
    validate_config || exit $?
    
    # Check prerequisites
    check_restic || exit $?
    
    # Phase 1: Scan directories and update .dirlist
    log_progress "=== PHASE 1: Directory Scanning ==="
    scan_directories || exit $?
    
    # Phase 2: Sequential backup processing
    log_progress "=== PHASE 2: Sequential Backup Processing ==="
    
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
        
        # Process each enabled directory
        for dir_name in "${!DIRLIST_ARRAY[@]}"; do
            if [[ "${DIRLIST_ARRAY[$dir_name]}" == "true" ]]; then
                processed_count=$((processed_count + 1))
                log_progress "Processing directory $processed_count of $enabled_count: $dir_name"
                log_debug "About to call process_directory for: $dir_name"
                
                if process_directory "$dir_name"; then
                    log_info "Successfully completed processing: $dir_name"
                else
                    local exit_code=$?
                    log_error "Failed to process directory: $dir_name (exit code: $exit_code)"
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
    
    log_progress "=== Docker Stack Selective Sequential Backup Completed (OPTIMIZED) ==="
    log_progress "Start time: $start_time"
    log_progress "End time: $end_time"
    log_progress "Directories enabled: $enabled_count"
    log_progress "Directories processed: $processed_count"
    log_progress "Directories failed: $failed_count"
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Some directories failed to process. Check logs for details."
        exit $first_failure_exit_code
    fi
    
    exit $EXIT_SUCCESS
}

####
# Script Entry Point
####

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
