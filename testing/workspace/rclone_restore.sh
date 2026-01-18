#!/bin/bash

# rclone_restore.sh - Stage 3: Cloud Restore Download
# Downloads restic repository from cloud storage for disaster recovery
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
LOG_FILE="${LOG_DIR}/rclone_restore.log"
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

    # Set defaults
    RCLONE_REMOTE="${RCLONE_REMOTE:-}"
    RCLONE_BACKUP_PATH="${RCLONE_BACKUP_PATH:-/backup/restic}"
    RCLONE_RESTORE_DIR="${RCLONE_RESTORE_DIR:-}"
    RCLONE_LOG_FILE="${RCLONE_LOG_FILE:-$LOG_DIR/rclone_restore.log}"
    RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-4}"
    RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
    RCLONE_BANDWIDTH="${RCLONE_BANDWIDTH:-}"
}

#######################################
# Validation Functions
#######################################

validate_config() {
    local restore_target="$1"
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

    # Check backup path is set
    if [[ -z "$RCLONE_BACKUP_PATH" ]]; then
        log_error "RCLONE_BACKUP_PATH not configured"
        ((errors++))
    fi

    # Validate restore target
    if [[ -z "$restore_target" ]]; then
        log_error "Restore target directory not specified"
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
# Restore Functions
#######################################

# Prepare restore directory
prepare_restore_directory() {
    local restore_dir="$1"

    log_info "Preparing restore directory: $restore_dir"

    # Check if directory exists
    if [[ -d "$restore_dir" ]]; then
        # Check if it's empty
        if [[ -n "$(ls -A "$restore_dir" 2>/dev/null)" ]]; then
            log_warn "Restore directory is not empty: $restore_dir"

            # In non-interactive mode, fail
            if [[ "${FORCE:-false}" != "true" ]]; then
                log_error "Use --force to overwrite existing files"
                return 1
            fi

            log_warn "Force mode enabled, proceeding with restore"
        fi
    else
        # Create directory
        if ! mkdir -p "$restore_dir"; then
            log_error "Failed to create restore directory: $restore_dir"
            return 1
        fi
        log_info "Created restore directory: $restore_dir"
    fi

    # Check if directory is writable
    if [[ ! -w "$restore_dir" ]]; then
        log_error "Restore directory not writable: $restore_dir"
        return 1
    fi

    return 0
}

# Perform the restore with retry logic
restore_with_retry() {
    local restore_dir="$1"
    local retries="$RCLONE_RETRIES"
    local attempt=1
    local source="${RCLONE_REMOTE}:${RCLONE_BACKUP_PATH}"

    log_info "Starting restore from: $source"
    log_info "Destination: $restore_dir"
    log_info "Transfers: $RCLONE_TRANSFERS"

    while [[ $attempt -le $retries ]]; do
        log_progress "Restore attempt $attempt of $retries"

        # Build rclone command
        local -a rclone_cmd=(
            rclone copy
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

        # Add source and destination
        rclone_cmd+=("$source" "$restore_dir")

        log_debug "Command: ${rclone_cmd[*]}"

        # Execute restore
        if "${rclone_cmd[@]}"; then
            log_info "Restore completed successfully"
            return 0
        fi

        local exit_code=$?
        log_warn "Restore attempt $attempt failed with exit code: $exit_code"
        ((attempt++))

        if [[ $attempt -le $retries ]]; then
            local wait_time=$((attempt * 30))
            log_info "Waiting ${wait_time} seconds before retry..."
            sleep "$wait_time"
        fi
    done

    log_error "Restore failed after $retries attempts"
    return 1
}

# Verify restored data
verify_restore() {
    local restore_dir="$1"

    log_info "Verifying restored data..."

    # Check directory has content
    if [[ -z "$(ls -A "$restore_dir" 2>/dev/null)" ]]; then
        log_error "Restore directory is empty after restore"
        return 1
    fi

    # Count files
    local file_count
    file_count="$(find "$restore_dir" -type f | wc -l)"
    log_info "Restored $file_count files"

    # Check for restic repository structure (if restoring restic repo)
    if [[ -d "$restore_dir/data" && -d "$restore_dir/keys" ]]; then
        log_info "Detected restic repository structure"

        # Check config file exists
        if [[ -f "$restore_dir/config" ]]; then
            log_info "Restic repository config found"
        else
            log_warn "Restic repository config not found - repository may be incomplete"
        fi
    fi

    # Calculate total size
    local total_size
    total_size="$(du -sh "$restore_dir" 2>/dev/null | cut -f1)"
    log_info "Total restored size: $total_size"

    return 0
}

#######################################
# Usage and Help
#######################################

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [RESTORE_DIR]

Stage 3: Cloud Restore Download
Downloads restic repository from cloud storage for disaster recovery.

ARGUMENTS:
    RESTORE_DIR         Target directory for restored data
                        (default: from config or /tmp/restored_backup_TIMESTAMP)

OPTIONS:
    -v, --verbose       Enable verbose output
    -n, --dry-run       Show what would be restored without downloading
    -f, --force         Overwrite existing files in restore directory
    -h, --help          Show this help message
    --test              Test connectivity only, don't restore
    --verify            Verify restored data after download

CONFIGURATION:
    Configuration is read from: $CONFIG_DIR/rclone.conf

    Required settings:
        RCLONE_REMOTE       - Name of rclone remote (from 'rclone config')
        RCLONE_BACKUP_PATH  - Path on remote where backups are stored

    Optional settings:
        RCLONE_RESTORE_DIR  - Default restore directory
        RCLONE_TRANSFERS    - Number of concurrent transfers (default: 4)
        RCLONE_RETRIES      - Number of retry attempts (default: 3)
        RCLONE_BANDWIDTH    - Bandwidth limit (e.g., "1M", "500k")

EXAMPLES:
    $SCRIPT_NAME /tmp/restore         # Restore to /tmp/restore
    $SCRIPT_NAME --dry-run            # Preview what would be restored
    $SCRIPT_NAME --test               # Test remote connectivity only
    $SCRIPT_NAME -f /opt/backup       # Force restore to /opt/backup
    $SCRIPT_NAME --verify /tmp/data   # Restore and verify

POST-RESTORE:
    After restoring a restic repository, you can use it with:

    export RESTIC_REPOSITORY=/path/to/restored/repo
    export RESTIC_PASSWORD=your-password
    restic snapshots  # List available snapshots
    restic restore latest --target /restore/path  # Restore files

EXIT CODES:
    0 - Success
    1 - Configuration error
    2 - Validation error
    3 - Restore error

EOF
}

#######################################
# Main Execution
#######################################

main() {
    local dry_run=false
    local test_only=false
    local verify=false
    local restore_dir=""
    FORCE=false

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
            -f|--force)
                FORCE=true
                shift
                ;;
            --test)
                test_only=true
                shift
                ;;
            --verify)
                verify=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                restore_dir="$1"
                shift
                ;;
        esac
    done

    log_info "=== Rclone Cloud Restore Started ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Time: $(date '+%Y-%m-%d %H:%M:%S')"

    # Load configuration
    load_rclone_config

    # Set restore directory (argument > config > default)
    if [[ -z "$restore_dir" ]]; then
        if [[ -n "$RCLONE_RESTORE_DIR" ]]; then
            restore_dir="$RCLONE_RESTORE_DIR"
        else
            restore_dir="/tmp/restored_backup_$(date +%Y%m%d_%H%M%S)"
        fi
    fi

    log_info "Restore target: $restore_dir"

    # Validate configuration
    if ! validate_config "$restore_dir"; then
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

        # Show remote contents
        log_info "Remote contents:"
        rclone lsd "${RCLONE_REMOTE}:${RCLONE_BACKUP_PATH}" --max-depth 1 2>/dev/null || \
            log_warn "Could not list remote contents"
        exit 0
    fi

    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Previewing restore operation..."
        rclone copy \
            --dry-run \
            --verbose \
            --links \
            "${RCLONE_REMOTE}:${RCLONE_BACKUP_PATH}" \
            "$restore_dir"
        exit $?
    fi

    # Prepare restore directory
    if ! prepare_restore_directory "$restore_dir"; then
        log_error "Failed to prepare restore directory"
        exit 2
    fi

    # Perform restore
    if ! restore_with_retry "$restore_dir"; then
        log_error "Cloud restore failed"
        exit 3
    fi

    # Verify if requested
    if [[ "$verify" == "true" ]]; then
        if ! verify_restore "$restore_dir"; then
            log_warn "Restore verification found issues"
        fi
    fi

    log_info "=== Rclone Cloud Restore Completed ==="
    log_info "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Restored to: $restore_dir"

    # Print next steps
    echo ""
    echo "Next steps:"
    echo "  1. Verify the restored data in: $restore_dir"
    echo "  2. If this is a restic repository, use it with:"
    echo "     export RESTIC_REPOSITORY=$restore_dir"
    echo "     restic snapshots"
    echo ""

    exit 0
}

# Run main function
main "$@"
