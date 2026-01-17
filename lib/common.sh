#!/bin/bash

# Common Library for Docker Stack 3-Stage Backup System
# Shared utilities, logging, security functions, and file locking
# Version: 1.0

# Prevent multiple sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
readonly _COMMON_SH_LOADED=1

#######################################
# Configuration
#######################################

# Color codes for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m' # No Color

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_CONFIG_ERROR=1
readonly EXIT_VALIDATION_ERROR=2
readonly EXIT_BACKUP_ERROR=3
readonly EXIT_DOCKER_ERROR=4
readonly EXIT_SIGNAL_ERROR=5
readonly EXIT_LOCK_ERROR=6

# Cleanup handlers array
declare -a CLEANUP_HANDLERS=()

# Lock file descriptor
LOCK_FD=200

#######################################
# Logging Functions
#######################################

# Internal log function
_log_internal() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Write to log file if defined
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Output to console based on level and verbosity
    local should_output=false
    case "$level" in
        ERROR|WARN) should_output=true ;;
        INFO) [[ "${VERBOSE:-false}" == "true" ]] && should_output=true ;;
        DEBUG) [[ "${DEBUG:-false}" == "true" ]] && should_output=true ;;
        PROGRESS) should_output=true ;;
    esac

    if [[ "$should_output" == "true" ]]; then
        case "$level" in
            ERROR)
                echo -e "${COLOR_RED}[$timestamp] [ERROR] $message${COLOR_NC}" >&2
                ;;
            WARN)
                echo -e "${COLOR_YELLOW}[$timestamp] [WARN] $message${COLOR_NC}" >&2
                ;;
            INFO)
                echo -e "${COLOR_GREEN}[$timestamp] [INFO] $message${COLOR_NC}"
                ;;
            DEBUG)
                echo -e "${COLOR_BLUE}[$timestamp] [DEBUG] $message${COLOR_NC}"
                ;;
            PROGRESS)
                echo -e "${COLOR_CYAN}[$timestamp] [PROGRESS] $message${COLOR_NC}"
                ;;
            *)
                echo "[$timestamp] [$level] $message"
                ;;
        esac
    fi
}

# Convenience logging functions
log_info() { _log_internal "INFO" "$@"; }
log_warn() { _log_internal "WARN" "$@"; }
log_error() { _log_internal "ERROR" "$@"; }
log_debug() { _log_internal "DEBUG" "$@"; }
log_progress() { _log_internal "PROGRESS" "$@"; }

#######################################
# Input Validation & Sanitization
#######################################

# Sanitize file path - removes dangerous characters and path traversal
# Usage: sanitized_path=$(sanitize_path "$input_path")
# Returns: 0 on success, 1 on invalid input
sanitize_path() {
    local input="$1"

    # Check for empty input
    if [[ -z "$input" ]]; then
        return 1
    fi

    # Remove path traversal attempts
    local sanitized="$input"
    sanitized="${sanitized//..\/}"
    sanitized="${sanitized//..\\/}"
    sanitized="${sanitized//..}"

    # Remove null bytes
    sanitized="${sanitized//$'\0'/}"

    # Remove dangerous shell characters
    sanitized="$(printf '%s' "$sanitized" | tr -d ';|&`$(){}[]<>!\\')"

    # Remove leading/trailing whitespace
    sanitized="$(echo "$sanitized" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Validate result
    if [[ -z "$sanitized" ]]; then
        return 1
    fi

    # Block paths starting with dash (could be interpreted as options)
    if [[ "$sanitized" == -* ]]; then
        return 1
    fi

    printf '%s' "$sanitized"
    return 0
}

# Sanitize filename - stricter than path, no slashes allowed
# Usage: sanitized_name=$(sanitize_filename "$input_name")
sanitize_filename() {
    local input="$1"

    if [[ -z "$input" ]]; then
        return 1
    fi

    # Remove all slashes and dangerous characters
    local sanitized
    sanitized="$(printf '%s' "$input" | tr -d '/\\;|&`$(){}[]<>!:*?"'"'")"

    # Remove null bytes
    sanitized="${sanitized//$'\0'/}"

    # Remove leading/trailing whitespace and dots
    sanitized="$(echo "$sanitized" | sed 's/^[[:space:]\.]*//;s/[[:space:]\.]*$//')"

    if [[ -z "$sanitized" || "$sanitized" == -* ]]; then
        return 1
    fi

    printf '%s' "$sanitized"
    return 0
}

# Validate and sanitize command for password retrieval
# Returns 0 if command is safe, 1 if dangerous patterns detected
sanitize_command() {
    local input="$1"

    if [[ -z "$input" ]]; then
        return 1
    fi

    # Check for dangerous patterns
    # Block: command chaining (;, &&, ||), pipes, backticks, command substitution
    if [[ "$input" =~ [\;\&\|] ]] || \
       [[ "$input" =~ \`.*\` ]] || \
       [[ "$input" =~ \$\( ]] || \
       [[ "$input" =~ \$\{ ]] || \
       [[ "$input" =~ \<\( ]] || \
       [[ "$input" =~ \>\( ]] || \
       [[ "$input" =~ \>\> ]] || \
       [[ "$input" =~ \< ]] || \
       [[ "$input" =~ \> ]]; then
        log_error "Command contains unsafe patterns: $input"
        return 1
    fi

    printf '%s' "$input"
    return 0
}

# Validate directory name - only safe characters allowed
# Usage: validate_directory_name "my-docker-stack"
validate_directory_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        log_error "Directory name cannot be empty"
        return 1
    fi

    # Allow only alphanumeric, dash, underscore, dot
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid directory name (unsafe characters): $name"
        return 1
    fi

    # Block names that are just dots
    if [[ "$name" =~ ^\.+$ ]]; then
        log_error "Invalid directory name (dots only): $name"
        return 1
    fi

    # Block hidden directories (starting with dot)
    if [[ "$name" == .* ]]; then
        log_debug "Skipping hidden directory: $name"
        return 1
    fi

    return 0
}

# Execute password command safely without eval
# Usage: password=$(execute_password_command "pass show backup/restic")
execute_password_command() {
    local cmd="$1"

    # Validate command first
    if ! sanitize_command "$cmd" >/dev/null; then
        log_error "Password command failed validation"
        return 1
    fi

    # List of known-safe command prefixes
    local -a allowed_prefixes=(
        "pass show"
        "pass "
        "gpg --decrypt"
        "gpg -d"
        "cat "
        "security find-generic-password"
        "secret-tool lookup"
        "kwallet-query"
        "echo "  # Allow for testing, but warn
    )

    local is_known_safe=false
    for prefix in "${allowed_prefixes[@]}"; do
        if [[ "$cmd" == "$prefix"* ]]; then
            is_known_safe=true
            break
        fi
    done

    if [[ "$is_known_safe" != "true" ]]; then
        log_warn "Password command doesn't match known-safe patterns: ${cmd:0:30}..."
        log_warn "Proceeding with caution"
    fi

    # Execute using bash -c (safer than eval)
    # Note: --restricted doesn't work well with all commands, so we use regular bash
    local result
    if result="$(bash -c "$cmd" 2>/dev/null)"; then
        if [[ -n "$result" ]]; then
            printf '%s' "$result"
            return 0
        else
            log_error "Password command returned empty result"
            return 1
        fi
    else
        log_error "Password command execution failed"
        return 1
    fi
}

#######################################
# File Locking Functions
#######################################

# Acquire exclusive lock on a file
# Usage: acquire_lock "/path/to/lockfile" [timeout_seconds]
acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-10}"

    # Create lock file directory if needed
    local lock_dir
    lock_dir="$(dirname "$lock_file")"
    if [[ ! -d "$lock_dir" ]]; then
        mkdir -p "$lock_dir" 2>/dev/null || {
            log_error "Cannot create lock directory: $lock_dir"
            return 1
        }
    fi

    # Open lock file descriptor
    # Using eval to set the file descriptor dynamically
    if ! eval "exec $LOCK_FD>\"$lock_file\"" 2>/dev/null; then
        log_error "Cannot open lock file: $lock_file"
        return 1
    fi

    # Try to acquire lock with timeout
    if ! flock -w "$timeout" $LOCK_FD 2>/dev/null; then
        log_error "Failed to acquire lock: $lock_file (timeout: ${timeout}s)"
        log_error "Another process may be holding the lock"
        return 1
    fi

    log_debug "Acquired lock: $lock_file"
    return 0
}

# Release lock
# Usage: release_lock
release_lock() {
    flock -u $LOCK_FD 2>/dev/null || true
    log_debug "Released lock"
}

# Execute a function while holding a lock
# Usage: with_lock "/path/to/lockfile" function_name [args...]
with_lock() {
    local lock_file="$1"
    shift
    local timeout="${LOCK_TIMEOUT:-30}"

    if ! acquire_lock "$lock_file" "$timeout"; then
        return $EXIT_LOCK_ERROR
    fi

    # Execute the command/function
    "$@"
    local result=$?

    release_lock
    return $result
}

#######################################
# Temp File Management
#######################################

# Create a temporary file with automatic cleanup registration
# Usage: temp_file=$(create_temp_file [suffix])
create_temp_file() {
    local suffix="${1:-}"
    local temp_file

    if [[ -n "$suffix" ]]; then
        temp_file="$(mktemp --suffix="$suffix")"
    else
        temp_file="$(mktemp)"
    fi

    if [[ -z "$temp_file" || ! -f "$temp_file" ]]; then
        log_error "Failed to create temporary file"
        return 1
    fi

    # Restrict permissions
    chmod 600 "$temp_file"

    # Register for cleanup
    register_cleanup "rm -f '$temp_file'"

    printf '%s' "$temp_file"
    return 0
}

# Create a temporary directory with automatic cleanup registration
# Usage: temp_dir=$(create_temp_dir [prefix])
create_temp_dir() {
    local prefix="${1:-backup}"
    local temp_dir

    temp_dir="$(mktemp -d -t "${prefix}.XXXXXX")"

    if [[ -z "$temp_dir" || ! -d "$temp_dir" ]]; then
        log_error "Failed to create temporary directory"
        return 1
    fi

    # Restrict permissions
    chmod 700 "$temp_dir"

    # Register for cleanup
    register_cleanup "rm -rf '$temp_dir'"

    printf '%s' "$temp_dir"
    return 0
}

# Register a cleanup command to run on exit
# Usage: register_cleanup "rm -f /tmp/myfile"
register_cleanup() {
    CLEANUP_HANDLERS+=("$1")
}

# Run all registered cleanup handlers
# This is typically called from a trap handler
run_cleanup_handlers() {
    local handler
    for handler in "${CLEANUP_HANDLERS[@]:-}"; do
        log_debug "Running cleanup: $handler"
        eval "$handler" 2>/dev/null || true
    done
}

#######################################
# Configuration Functions
#######################################

# Parse a configuration file and export variables
# Usage: parse_config_file "/path/to/config.conf"
parse_config_file() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return $EXIT_CONFIG_ERROR
    fi

    if [[ ! -r "$config_file" ]]; then
        log_error "Configuration file not readable: $config_file"
        return $EXIT_CONFIG_ERROR
    fi

    # Check file permissions for security
    local perms
    perms="$(stat -c %a "$config_file" 2>/dev/null)"
    if [[ -n "$perms" ]]; then
        # Warn if group or others can read
        local group_other="${perms:1:2}"
        if [[ "$group_other" != "00" ]]; then
            log_warn "Configuration file has permissive permissions: $config_file ($perms)"
            log_warn "Consider: chmod 600 $config_file"
        fi
    fi

    # Parse configuration - only lines matching KEY=value pattern
    local key value
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Clean up key (trim whitespace)
        key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        # Skip if key doesn't look valid
        [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] && continue

        # Clean up value: remove comments, trim whitespace, remove quotes
        value="$(echo "$value" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
        value="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"

        # Export the variable
        export "$key=$value"
        log_debug "Loaded config: $key=${value:0:20}..."

    done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$config_file" 2>/dev/null || true)

    return 0
}

# Validate that required configuration variables are set
# Usage: validate_required_config "VAR1" "VAR2" "VAR3"
validate_required_config() {
    local missing=0
    local var_name

    for var_name in "$@"; do
        local var_value
        eval "var_value=\${$var_name:-}"

        if [[ -z "$var_value" ]]; then
            log_error "Required configuration missing: $var_name"
            ((missing++))
        fi
    done

    return $missing
}

#######################################
# Utility Functions
#######################################

# Check if a command exists
# Usage: command_exists "docker" && echo "Docker is available"
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check disk space in MB
# Usage: available_mb=$(get_available_space_mb "/path")
get_available_space_mb() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        echo "0"
        return 1
    fi

    df -BM "$path" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/M//'
}

# Check if running as root
is_root() {
    [[ "$(id -u)" == "0" ]]
}

# Get the script directory (for sourcing scripts)
# Usage: source "$(get_script_dir)/other_script.sh"
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

#######################################
# Rclone Validation Functions
#######################################

# Validate that an rclone remote is configured
# Usage: validate_rclone_remote "my-remote"
validate_rclone_remote() {
    local remote_name="$1"

    if ! command_exists rclone; then
        log_error "rclone is not installed"
        return 1
    fi

    # Check if remote exists in rclone config
    if ! rclone listremotes 2>/dev/null | grep -q "^${remote_name}:$"; then
        log_error "Rclone remote not configured: $remote_name"
        log_error "Available remotes: $(rclone listremotes 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    return 0
}

# Test connectivity to an rclone remote
# Usage: test_rclone_connectivity "my-remote" [retries]
test_rclone_connectivity() {
    local remote_name="$1"
    local retries="${2:-3}"
    local attempt=1

    while [[ $attempt -le $retries ]]; do
        log_info "Testing connectivity to $remote_name (attempt $attempt/$retries)"

        if rclone lsd "${remote_name}:" --max-depth 0 >/dev/null 2>&1; then
            log_info "Successfully connected to $remote_name"
            return 0
        fi

        log_warn "Connection attempt $attempt failed"
        ((attempt++))

        if [[ $attempt -le $retries ]]; then
            sleep 5
        fi
    done

    log_error "Failed to connect to remote after $retries attempts: $remote_name"
    return 1
}

#######################################
# Dirlist Validation Functions
#######################################

# Validate dirlist file format
# Usage: validate_dirlist_file "/path/to/dirlist"
validate_dirlist_file() {
    local dirlist_file="$1"
    local errors=0
    local line_num=0

    if [[ ! -f "$dirlist_file" ]]; then
        log_error "Dirlist file not found: $dirlist_file"
        return 1
    fi

    while IFS= read -r line; do
        ((line_num++))

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Check format: name=true|false
        if [[ ! "$line" =~ ^[a-zA-Z0-9._-]+=(true|false)$ ]]; then
            log_error "Invalid format at line $line_num: $line"
            ((errors++))
            continue
        fi

        # Extract and validate directory name
        local dir_name="${line%%=*}"
        if ! validate_directory_name "$dir_name" 2>/dev/null; then
            log_error "Invalid directory name at line $line_num: $dir_name"
            ((errors++))
        fi
    done < "$dirlist_file"

    return $errors
}

#######################################
# Password Security Functions
#######################################

# Setup restic password securely (never exports raw password to environment)
# Usage: setup_secure_restic_password
setup_secure_restic_password() {
    local password_file="${RESTIC_PASSWORD_FILE:-}"
    local password_command="${RESTIC_PASSWORD_COMMAND:-}"
    local direct_password="${RESTIC_PASSWORD:-}"
    local enable_file="${ENABLE_PASSWORD_FILE:-false}"
    local enable_command="${ENABLE_PASSWORD_COMMAND:-false}"

    # Priority: password file > password command > direct password (converted to file)

    if [[ "$enable_file" == "true" && -n "$password_file" ]]; then
        log_info "Using password file authentication"

        # Validate file exists
        if [[ ! -f "$password_file" ]]; then
            log_error "Password file not found: $password_file"
            return 1
        fi

        # Validate file permissions (must be 600 or 400)
        local perms
        perms="$(stat -c %a "$password_file" 2>/dev/null)"
        if [[ ! "$perms" =~ ^[46]00$ ]]; then
            log_error "Password file permissions too open: $perms (must be 600 or 400)"
            log_error "Fix with: chmod 600 $password_file"
            return 1
        fi

        export RESTIC_PASSWORD_FILE="$password_file"
        unset RESTIC_PASSWORD

    elif [[ "$enable_command" == "true" && -n "$password_command" ]]; then
        log_info "Using password command authentication"

        # Validate command is safe
        if ! sanitize_command "$password_command" >/dev/null; then
            log_error "Password command contains unsafe patterns"
            return 1
        fi

        # Test that command works
        local test_result
        if ! test_result="$(execute_password_command "$password_command")"; then
            log_error "Password command failed to execute"
            return 1
        fi

        if [[ -z "$test_result" ]]; then
            log_error "Password command returned empty password"
            return 1
        fi

        export RESTIC_PASSWORD_COMMAND="$password_command"
        unset RESTIC_PASSWORD

    elif [[ -n "$direct_password" ]]; then
        log_info "Using direct password (converting to secure file)"

        # Create a secure temporary password file
        local temp_pass_file
        temp_pass_file="$(mktemp)"
        chmod 600 "$temp_pass_file"

        # Write password to file
        printf '%s' "$direct_password" > "$temp_pass_file"

        # Register cleanup
        register_cleanup "rm -f '$temp_pass_file'"

        # Export file path, clear password from environment
        export RESTIC_PASSWORD_FILE="$temp_pass_file"
        unset RESTIC_PASSWORD

        log_debug "Created secure password file: $temp_pass_file"

    else
        log_error "No password method configured"
        return 1
    fi

    return 0
}

#######################################
# Initialization
#######################################

# Initialize common library (call this at the start of scripts)
# Usage: init_common [log_file_path]
init_common() {
    local log_file="${1:-}"

    if [[ -n "$log_file" ]]; then
        LOG_FILE="$log_file"

        # Ensure log directory exists
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || {
                echo "Warning: Cannot create log directory: $log_dir" >&2
            }
        fi
    fi

    log_debug "Common library initialized"
}

# Export functions for use in subshells
export -f log_info log_warn log_error log_debug log_progress
export -f sanitize_path sanitize_filename sanitize_command validate_directory_name
export -f acquire_lock release_lock with_lock
export -f create_temp_file create_temp_dir register_cleanup run_cleanup_handlers
export -f command_exists get_available_space_mb is_root
