
#!/bin/bash

# Script to remove version lines from Docker Compose files - OPTIMIZED VERSION
# Usage: ./remove-version-lines.sh [directory]
# Author: Generated for Docker compose maintenance
# Version: 2.0 - Enhanced with better error handling and logging

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
readonly EXIT_PROCESSING_ERROR=3

# Statistics tracking
declare -i TOTAL_FILES_FOUND=0
declare -i TOTAL_FILES_PROCESSED=0
declare -i TOTAL_LINES_REMOVED=0
declare -i TOTAL_ERRORS=0

####
# Logging Functions
####

# Enhanced log message with timestamp and colors
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
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
        SUCCESS)
            echo -e "${GREEN}[$timestamp] [SUCCESS] $message${NC}"
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
log_success() { log_message "SUCCESS" "$@"; }

####
# Utility Functions
####

# Function to show usage information
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [directory]

Remove version lines from Docker Compose files - OPTIMIZED VERSION

This script removes version lines from Docker Compose files in top-level
subdirectories. Enhanced with better error handling, logging, and statistics.

ARGUMENTS:
    directory    Path to directory to scan (default: current directory)

OPTIONS:
    -v, --verbose    Enable verbose output with detailed processing info
    -n, --dry-run    Show what would be done without making changes
    -h, --help       Display this help message

ENHANCEMENTS APPLIED:
    - Enhanced error handling and recovery
    - Detailed statistics and progress reporting
    - Dry-run mode for safe testing
    - Verbose logging with timestamps
    - Better file validation and safety checks
    - Improved backup handling

EXAMPLES:
    $SCRIPT_NAME                           # Scan current directory
    $SCRIPT_NAME /path/to/docker/stacks    # Scan specific directory
    $SCRIPT_NAME --verbose ~/projects      # Scan with verbose output
    $SCRIPT_NAME --dry-run /srv/docker     # Test run without changes

The script will:
    - Look for docker-compose.yml, compose.yml, docker-compose.yaml, compose.yaml
    - Remove any lines starting with 'version:' (with optional whitespace)
    - Create backups with .bak extension during processing
    - Provide detailed output of all operations
    - Show comprehensive statistics at completion

EXIT CODES:
    0 - Success (all files processed successfully)
    1 - Configuration error (invalid arguments)
    2 - Validation error (directory issues)
    3 - Processing error (some files failed)

EOF
}

# Validate target directory
validate_directory() {
    local target_dir="$1"
    
    if [[ ! -d "$target_dir" ]]; then
        log_error "Directory '$target_dir' does not exist"
        return $EXIT_VALIDATION_ERROR
    fi
    
    if [[ ! -r "$target_dir" ]]; then
        log_error "Directory '$target_dir' is not readable"
        return $EXIT_VALIDATION_ERROR
    fi
    
    log_info "Target directory validated: $target_dir"
    return $EXIT_SUCCESS
}

# Find Docker compose files in directory
find_compose_files() {
    local target_dir="$1"
    local -a compose_files=()
    
    log_progress "Scanning for Docker compose files in: $target_dir"
    
    # Find all compose files in top-level subdirectories
    while IFS= read -r -d '' file; do
        compose_files+=("$file")
        ((TOTAL_FILES_FOUND++))
        log_debug "Found compose file: $file"
    done < <(find "$target_dir" -maxdepth 2 -type f \( \
        -name "docker-compose.yml" -o \
        -name "docker-compose.yaml" -o \
        -name "compose.yml" -o \
        -name "compose.yaml" \
    \) -print0 2>/dev/null)
    
    log_info "Found $TOTAL_FILES_FOUND Docker compose files"
    
    # Return the array
    printf '%s\n' "${compose_files[@]}"
}

# Process a single compose file
process_compose_file() {
    local file_path="$1"
    local dry_run="$2"
    local verbose="$3"
    
    log_progress "Processing file: $file_path"
    
    # Validate file exists and is readable
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        ((TOTAL_ERRORS++))
        return 1
    fi
    
    if [[ ! -r "$file_path" ]]; then
        log_error "File not readable: $file_path"
        ((TOTAL_ERRORS++))
        return 1
    fi
    
    # Check if file contains version lines
    local version_lines
    version_lines="$(grep -n '^[[:space:]]*version:' "$file_path" 2>/dev/null || true)"
    
    if [[ -z "$version_lines" ]]; then
        if [[ "$verbose" == "true" ]]; then
            log_info "No version lines found in: $file_path"
        fi
        return 0
    fi
    
    local line_count
    line_count="$(echo "$version_lines" | wc -l)"
    
    log_info "Found $line_count version line(s) in: $file_path"
    
    if [[ "$verbose" == "true" ]]; then
        echo "$version_lines" | while IFS= read -r line; do
            log_debug "  $line"
        done
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would remove $line_count version line(s) from: $file_path"
        TOTAL_LINES_REMOVED=$((TOTAL_LINES_REMOVED + line_count))
        return 0
    fi
    
    # Create backup
    local backup_file="${file_path}.bak"
    if ! cp "$file_path" "$backup_file"; then
        log_error "Failed to create backup: $backup_file"
        ((TOTAL_ERRORS++))
        return 1
    fi
    
    log_debug "Created backup: $backup_file"
    
    # Remove version lines
    if sed -i '/^[[:space:]]*version:/d' "$file_path"; then
        log_success "Removed $line_count version line(s) from: $file_path"
        TOTAL_LINES_REMOVED=$((TOTAL_LINES_REMOVED + line_count))
        
        # Verify the changes
        local remaining_version_lines
        remaining_version_lines="$(grep -n '^[[:space:]]*version:' "$file_path" 2>/dev/null || true)"
        
        if [[ -n "$remaining_version_lines" ]]; then
            log_warn "Some version lines may still remain in: $file_path"
            if [[ "$verbose" == "true" ]]; then
                echo "$remaining_version_lines" | while IFS= read -r line; do
                    log_warn "  Remaining: $line"
                done
            fi
        fi
        
        # Remove backup if successful and no remaining version lines
        if [[ -z "$remaining_version_lines" ]]; then
            rm -f "$backup_file"
            log_debug "Removed backup file: $backup_file"
        else
            log_info "Kept backup file due to remaining version lines: $backup_file"
        fi
        
    else
        log_error "Failed to remove version lines from: $file_path"
        log_info "Backup preserved at: $backup_file"
        ((TOTAL_ERRORS++))
        return 1
    fi
    
    return 0
}

# Show processing statistics
show_statistics() {
    local start_time="$1"
    local end_time="$2"
    
    log_progress "=== Processing Statistics ==="
    log_info "Start time: $start_time"
    log_info "End time: $end_time"
    log_info "Files found: $TOTAL_FILES_FOUND"
    log_info "Files processed: $TOTAL_FILES_PROCESSED"
    log_info "Version lines removed: $TOTAL_LINES_REMOVED"
    log_info "Errors encountered: $TOTAL_ERRORS"
    
    if [[ $TOTAL_ERRORS -eq 0 ]]; then
        log_success "All files processed successfully!"
    else
        log_warn "$TOTAL_ERRORS error(s) encountered during processing"
    fi
}

####
# Main Execution Flow
####

# Parse command line arguments
parse_arguments() {
    local target_dir="."
    local dry_run=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit $EXIT_CONFIG_ERROR
                ;;
            *)
                target_dir="$1"
                shift
                ;;
        esac
    done
    
    # Return parsed values
    echo "$target_dir|$dry_run|$verbose"
}

# Main function
main() {
    local start_time
    start_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    log_info "=== Docker Compose Version Line Removal Started (OPTIMIZED) ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "PID: $$"
    log_info "Start time: $start_time"
    
    # Parse arguments
    local parsed_args
    parsed_args="$(parse_arguments "$@")"
    
    local target_dir
    local dry_run
    local verbose
    IFS='|' read -r target_dir dry_run verbose <<< "$parsed_args"
    
    log_info "Target directory: $target_dir"
    log_info "Dry run mode: $dry_run"
    log_info "Verbose mode: $verbose"
    
    # Validate target directory
    validate_directory "$target_dir" || exit $?
    
    # Find compose files
    local -a compose_files
    mapfile -t compose_files < <(find_compose_files "$target_dir")
    
    if [[ ${#compose_files[@]} -eq 0 ]]; then
        log_warn "No Docker compose files found in: $target_dir"
        log_info "Looking for files: docker-compose.yml, docker-compose.yaml, compose.yml, compose.yaml"
        exit $EXIT_SUCCESS
    fi
    
    # Process each file
    log_progress "Processing $TOTAL_FILES_FOUND compose files..."
    
    for file_path in "${compose_files[@]}"; do
        if process_compose_file "$file_path" "$dry_run" "$verbose"; then
            ((TOTAL_FILES_PROCESSED++))
        fi
    done
    
    local end_time
    end_time="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Show statistics
    show_statistics "$start_time" "$end_time"
    
    # Exit with appropriate code
    if [[ $TOTAL_ERRORS -gt 0 ]]; then
        exit $EXIT_PROCESSING_ERROR
    else
        exit $EXIT_SUCCESS
    fi
}

####
# Script Entry Point
####

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
