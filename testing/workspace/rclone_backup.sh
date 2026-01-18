#!/bin/bash

# rclone_backup.sh - Stage 2: Cloud Sync Upload
# Syncs local restic repository to cloud storage with retry logic
# Part of Docker Stack 3-Stage Backup System
# Version: 2.0

set -eo pipefail

#######################################
# Script Configuration
#######################################

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$SCRIPT_DIR/../lib"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"
readonly LOG_DIR="$SCRIPT_DIR/../logs"

# Source common library
if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    echo "ERROR: Common library not found: $LIB_DIR/common.sh" >&2
    echo "Please run install.sh to set up the backup system" >&2
    exit 1
fi

# Initialize logging
LOG_FILE="${LOG_DIR}/rclone_backup.log"
VERBOSE="${VERBOSE:-false}"
init_common "$LOG_FILE"

#######################################
# Configuration Loading
#######################################

# Load rclone configuration
load_rclone_config() {
    local config_file="$CONFIG_DIR/rclone.conf"

    # Check for configuration file
    if [[ -f "$config_file" ]]; then
        log_info "Loading configuration from: $config_file"
        source "$config_file"
    else
        log_warn "Configuration file not found: $config_file"
        log_warn "Using environment variables or defaults"
    fi

    # Also try to load backup.conf for RESTIC_REPOSITORY as fallback
    local backup_config="$CONFIG_DIR/backup.conf"
    if [[ -f "$backup_config" && -z "${RCLONE_SOURCE_DIR:-}" ]]; then
        local restic_repo
        restic_repo="$(grep "^RESTIC_REPOSITORY=" "$backup_config" 2>/dev/null | cut -d= -f2 | sed 's/^["'\'']\|["'\'']$//g' || true)"
        if [[ -n "$restic_repo" && -d "$restic_repo" ]]; then
            RCLONE_SOURCE_DIR="$restic_repo"
            log_info "Using RESTIC_REPOSITORY as source: $RCLONE_SOURCE_DIR"
        fi
    fi

    # Set defaults
    RCLONE_REMOTE="${RCLONE_REMOTE:-}"
    RCLONE_SOURCE_DIR="${RCLONE_SOURCE_DIR:-}"
    RCLONE_BACKUP_PATH="${RCLONE_BACKUP_PATH:-/backup/restic}"
    RCLONE_LOG_FILE="${RCLONE_LOG_FILE:-$LOG_DIR/rclone_sync.log}"
    RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-4}"
    RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
    RCLONE_BANDWIDTH="${RCLONE_BANDWIDTH:-}"
    RCLONE_EXTRA_OPTIONS="${RCLONE_EXTRA_OPTIONS:-}"
}

#######################################
# Validation Functions
#######################################

validate_config() {
    local errors=0

    log_info "Validating configuration"

    # Check rclone is installed
    if ! command_exists rclone; then
        log_error "rclone is not installed"
        log_error "Install with: https://rclone.org/install/"
        ((errors++))
    fi

    # Check remote is configured
    if [[ -z "$RCLONE_REMOTE" ]]; then
        log_error "RCLONE_REMOTE not configured"
        log_error "Set in $CONFIG_DIR/rclone.conf or as environment variable"
        ((errors++))
    fi

    # Check source directory
    if [[ -z "$RCLONE_SOURCE_DIR" ]]; then
        log_error "RCLONE_SOURCE_DIR not configured"
        ((errors++))
    elif [[ ! -d "$RCLONE_SOURCE_DIR" ]]; then
        log_error "Source directory does not exist: $RCLONE_SOURCE_DIR"
        ((errors++))
    elif [[ ! -r "$RCLONE_SOURCE_DIR" ]]; then
        log_error "Source directory not readable: $RCLONE_SOURCE_DIR"
        ((errors++))
    fi

    # Check backup path is set
    if [[ -z "$RCLONE_BACKUP_PATH" ]]; then
        log_error "RCLONE_BACKUP_PATH not configured"
        ((errors++))
    fi

    # Validate remote exists in rclone config
    if [[ -n "$RCLONE_REMOTE" ]] && command_exists rclone; then
        if ! validate_rclone_remote "$RCLONE_REMOTE"; then
            ((errors++))
        fi
    fi

    # Validate numeric parameters
    if [[ ! "$RCLONE_TRANSFERS" =~ ^[0-9]+$ ]] || [[ "$RCLONE_TRANSFERS" -lt 1 ]]; then
        log_warn "Invalid RCLONE_TRANSFERS value: $RCLONE_TRANSFERS, using default: 4"
        RCLONE_TRANSFERS=4
    fi

    if [[ ! "$RCLONE_RETRIES" =~ ^[0-9]+$ ]] || [[ "$RCLONE_RETRIES" -lt 1 ]]; then
        log_warn "Invalid RCLONE_RETRIES value: $RCLONE_RETRIES, using default: 3"
        RCLONE_RETRIES=3
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi

    log_info "Configuration validation passed"
    return 0
}

#######################################
# Sync Functions
#######################################

# Perform the sync with retry logic
sync_with_retry() {
    local retries="$RCLONE_RETRIES"
    local attempt=1
    local destination="${RCLONE_REMOTE}:${RCLONE_BACKUP_PATH}"

    log_info "Starting sync to: $destination"
    log_info "Source: $RCLONE_SOURCE_DIR"
    log_info "Transfers: $RCLONE_TRANSFERS"

    while [[ $attempt -le $retries ]]; do
        log_progress "Sync attempt $attempt of $retries"

        # Build rclone command
        local -a rclone_cmd=(
            rclone sync
            --progress
            --links
            --transfers="$RCLONE_TRANSFERS"
            --retries=3
            --low-level-retries=10
            --stats=30s
            --stats-one-line
            --verbose
            --log-file="$RCLONE_LOG_FILE"
        )

        # Add bandwidth limit if configured
        if [[ -n "$RCLONE_BANDWIDTH" ]]; then
            rclone_cmd+=(--bwlimit="$RCLONE_BANDWIDTH")
            log_info "Bandwidth limit: $RCLONE_BANDWIDTH"
        fi

        # Add extra options if configured
        if [[ -n "$RCLONE_EXTRA_OPTIONS" ]]; then
            # shellcheck disable=SC2206
            rclone_cmd+=($RCLONE_EXTRA_OPTIONS)
        fi

        # Add source and destination
        rclone_cmd+=("$RCLONE_SOURCE_DIR" "$destination")

        log_debug "Command: ${rclone_cmd[*]}"

        # Execute sync
        if "${rclone_cmd[@]}"; then
            log_info "Sync completed successfully"
            return 0
        fi

        local exit_code=$?
        log_warn "Sync attempt $attempt failed with exit code: $exit_code"
        ((attempt++))

        if [[ $attempt -le $retries ]]; then
            local wait_time=$((attempt * 30))
            log_info "Waiting ${wait_time} seconds before retry..."
            sleep "$wait_time"
        fi
    done

    log_error "Sync failed after $retries attempts"
    return 1
}

#######################################
# Usage and Help
#######################################

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Stage 2: Cloud Sync Upload
Syncs local restic repository to cloud storage using rclone.

OPTIONS:
    -v, --verbose       Enable verbose output
    -n, --dry-run       Perform dry run (show what would be synced)
    -h, --help          Show this help message
    --test              Test connectivity only, don't sync

CONFIGURATION:
    Configuration is read from: $CONFIG_DIR/rclone.conf

    Required settings:
        RCLONE_REMOTE       - Name of rclone remote (from 'rclone config')
        RCLONE_SOURCE_DIR   - Local directory to sync
        RCLONE_BACKUP_PATH  - Path on remote for backups

    Optional settings:
        RCLONE_TRANSFERS    - Number of concurrent transfers (default: 4)
        RCLONE_RETRIES      - Number of retry attempts (default: 3)
        RCLONE_BANDWIDTH    - Bandwidth limit (e.g., "1M", "500k")

EXAMPLES:
    $SCRIPT_NAME                    # Run sync with default settings
    $SCRIPT_NAME --verbose          # Run with verbose output
    $SCRIPT_NAME --dry-run          # Preview what would be synced
    $SCRIPT_NAME --test             # Test remote connectivity only

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Validation error
    3 - Sync error

EOF
}

#######################################
# Main Execution
#######################################

main() {
    local dry_run=false
    local test_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            --test)
                test_only=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    log_info "=== Rclone Cloud Sync Started ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Time: $(date '+%Y-%m-%d %H:%M:%S')"

    # Load configuration
    load_rclone_config

    # Validate configuration
    if ! validate_config; then
        log_error "Configuration validation failed"
        exit 1
    fi

    # Test connectivity
    log_info "Testing remote connectivity..."
    if ! test_rclone_connectivity "$RCLONE_REMOTE" 3; then
        log_error "Failed to connect to remote: $RCLONE_REMOTE"
        exit 2
    fi

    # If test only, exit here
    if [[ "$test_only" == "true" ]]; then
        log_info "Connectivity test passed"
        log_info "Remote: $RCLONE_REMOTE"
        log_info "Path: $RCLONE_BACKUP_PATH"
        exit 0
    fi

    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Previewing sync operation..."
        rclone sync \
            --dry-run \
            --verbose \
            --links \
            "$RCLONE_SOURCE_DIR" \
            "${RCLONE_REMOTE}:${RCLONE_BACKUP_PATH}"
        exit $?
    fi

    # Perform sync
    if ! sync_with_retry; then
        log_error "Cloud sync failed"
        exit 3
    fi

    log_info "=== Rclone Cloud Sync Completed ==="
    log_info "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
}

# Run main function
main "$@"
