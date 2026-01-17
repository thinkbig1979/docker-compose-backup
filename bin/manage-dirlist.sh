#!/bin/bash

# Directory List Management TUI Script
# Interactive dialog-based interface for managing .dirlist file
# Author: Generated for backup script management
# Version: 1.1

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/../config/backup.conf}"
readonly DIRLIST_FILE="$SCRIPT_DIR/../dirlist"
readonly LOCK_DIR="$SCRIPT_DIR/../locks"
readonly LOCK_FILE="$LOCK_DIR/dirlist.lock"
readonly LIB_DIR="$SCRIPT_DIR/../lib"

# Source common library if available
if [[ -f "$LIB_DIR/common.sh" ]]; then
    # shellcheck source=../lib/common.sh
    source "$LIB_DIR/common.sh"
    COMMON_LIB_LOADED=true
else
    COMMON_LIB_LOADED=false
    # Exit codes (only define if common library not loaded, as it defines these)
    readonly EXIT_SUCCESS=0
    readonly EXIT_CONFIG_ERROR=1
    readonly EXIT_LOCK_ERROR=6
fi

# Default configuration
BACKUP_DIR=""

# Color codes for output (use different names to avoid conflict with common.sh)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Exit codes specific to this script (not in common.sh)
readonly EXIT_DIALOG_ERROR=2
readonly EXIT_USER_CANCEL=3

# Lock file descriptor (if common lib not available)
LOCK_FD=200
HAS_LOCK=false

# Terminal cleanup function
cleanup_terminal() {
    local exit_code=$?

    # Release lock if held
    if [[ "$HAS_LOCK" == "true" ]]; then
        release_dirlist_lock
    fi

    # Clear dialog artifacts and restore terminal
    clear 2>/dev/null || true
    # Reset terminal to normal state
    tput sgr0 2>/dev/null || true
    # Show cursor if it was hidden
    tput cnorm 2>/dev/null || true

    exit $exit_code
}

# Set up trap to ensure cleanup on exit
trap cleanup_terminal EXIT INT TERM

#######################################
# Utility Functions
#######################################

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

#######################################
# Locking Functions
#######################################

# Acquire lock on dirlist file to prevent concurrent modifications
acquire_dirlist_lock() {
    local timeout="${1:-30}"

    # Create lock directory if it doesn't exist
    if [[ ! -d "$LOCK_DIR" ]]; then
        mkdir -p "$LOCK_DIR" 2>/dev/null || {
            print_error "Cannot create lock directory: $LOCK_DIR"
            return 1
        }
    fi

    # Use common library if available
    if [[ "$COMMON_LIB_LOADED" == "true" ]]; then
        if acquire_lock "$LOCK_FILE" "$timeout"; then
            HAS_LOCK=true
            return 0
        else
            return 1
        fi
    fi

    # Fallback: manual flock implementation
    if ! eval "exec $LOCK_FD>\"$LOCK_FILE\"" 2>/dev/null; then
        print_error "Cannot open lock file: $LOCK_FILE"
        return 1
    fi

    if ! flock -w "$timeout" $LOCK_FD 2>/dev/null; then
        print_error "Failed to acquire lock on dirlist (timeout: ${timeout}s)"
        print_error "Another process may be modifying the directory list"
        return 1
    fi

    HAS_LOCK=true
    print_info "Acquired lock on directory list"
    return 0
}

# Release lock on dirlist file
release_dirlist_lock() {
    if [[ "$HAS_LOCK" != "true" ]]; then
        return 0
    fi

    # Use common library if available
    if [[ "$COMMON_LIB_LOADED" == "true" ]]; then
        release_lock
    else
        # Fallback: manual flock release
        flock -u $LOCK_FD 2>/dev/null || true
    fi

    HAS_LOCK=false
    return 0
}

#######################################
# Validation Functions
#######################################

# Validate directory name - only safe characters allowed
validate_dir_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 1
    fi

    # Use common library validation if available
    if [[ "$COMMON_LIB_LOADED" == "true" ]]; then
        validate_directory_name "$name" 2>/dev/null
        return $?
    fi

    # Fallback validation: allow only alphanumeric, dash, underscore, dot
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        return 1
    fi

    # Block names that are just dots
    if [[ "$name" =~ ^\.+$ ]]; then
        return 1
    fi

    # Block hidden directories (starting with dot)
    if [[ "$name" == .* ]]; then
        return 1
    fi

    return 0
}

# Validate dirlist file format and content
validate_dirlist_content() {
    local file="$1"
    local errors=0
    local line_num=0

    if [[ ! -f "$file" ]]; then
        print_warning "Dirlist file does not exist: $file"
        return 0  # Not an error - file will be created
    fi

    while IFS= read -r line; do
        ((line_num++))

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Check format: directory_name=true|false
        if [[ ! "$line" =~ ^[^=]+=(true|false)$ ]]; then
            print_error "Invalid format at line $line_num: $line"
            ((errors++))
            continue
        fi

        # Extract and validate directory name
        local dir_name="${line%%=*}"
        if ! validate_dir_name "$dir_name"; then
            print_error "Invalid directory name at line $line_num: $dir_name"
            ((errors++))
        fi
    done < "$file"

    if [[ $errors -gt 0 ]]; then
        print_error "Found $errors validation error(s) in dirlist file"
        return 1
    fi

    return 0
}

# Check if dialog command is available
check_dialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        print_error "The 'dialog' command is not installed or not in PATH"
        print_error "Please install dialog package:"
        print_error "  Ubuntu/Debian: sudo apt-get install dialog"
        print_error "  CentOS/RHEL: sudo yum install dialog"
        print_error "  Fedora: sudo dnf install dialog"
        exit $EXIT_DIALOG_ERROR
    fi
}

# Load configuration to get BACKUP_DIR
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        print_error "Please ensure backup.conf exists in the script directory"
        exit $EXIT_CONFIG_ERROR
    fi

    # Read configuration file and extract BACKUP_DIR
    local config_content
    config_content="$(grep -v '^[[:space:]]*#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | head -20)"

    if [[ -z "$config_content" ]]; then
        print_error "No valid configuration found in: $CONFIG_FILE"
        exit $EXIT_CONFIG_ERROR
    fi

    # Parse BACKUP_DIR from configuration
    while IFS='=' read -r key value; do
        # Strip inline comments and whitespace from value
        value="$(echo "$value" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        if [[ "$key" == "BACKUP_DIR" ]]; then
            BACKUP_DIR="$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')"
            break
        fi
    done <<< "$config_content"

    if [[ -z "$BACKUP_DIR" ]]; then
        print_error "BACKUP_DIR not found in configuration file"
        exit $EXIT_CONFIG_ERROR
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "Backup directory does not exist: $BACKUP_DIR"
        exit $EXIT_CONFIG_ERROR
    fi

    print_info "Using backup directory: $BACKUP_DIR"
}

# Discover Docker compose directories
discover_directories() {
    local found_dirs=()
    local dir_count=0

    print_info "Scanning for Docker compose directories in: $BACKUP_DIR"

    # Check if backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "Backup directory does not exist: $BACKUP_DIR"
        exit $EXIT_CONFIG_ERROR
    fi

    # Temporarily disable strict mode for this function
    set +e

    # Find all top-level subdirectories containing docker-compose files
    # Use a simpler approach with for loop
    for dir in "$BACKUP_DIR"/*; do
        # Skip if not a directory
        [[ -d "$dir" ]] || continue

        local dir_name
        dir_name="$(basename "$dir")"

        # Skip hidden directories
        if [[ "$dir_name" =~ ^\..*$ ]]; then
            continue
        fi

        # Check if directory contains docker-compose files
        if [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]] || [[ -f "$dir/compose.yml" ]] || [[ -f "$dir/compose.yaml" ]]; then
            found_dirs+=("$dir_name")
            ((dir_count++))
        fi
    done

    # Re-enable strict mode
    set -e

    print_info "Found $dir_count Docker compose directories"

    # Return the array via global variable
    DISCOVERED_DIRS=("${found_dirs[@]}")
}

# Load existing .dirlist file
load_dirlist() {
    local -A dirlist_array

    if [[ ! -f "$DIRLIST_FILE" ]]; then
        print_warning "Directory list file not found: $DIRLIST_FILE"
        print_info "Will create new .dirlist file based on discovered directories"
        return 1
    fi

    print_info "Loading existing directory list from: $DIRLIST_FILE"

    # Read the dirlist file and populate the associative array
    while IFS='=' read -r dir_name enabled; do
        # Skip comments and empty lines
        if [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]]; then
            continue
        fi

        # Validate format
        if [[ "$enabled" =~ ^(true|false)$ ]]; then
            dirlist_array["$dir_name"]="$enabled"
        fi
    done < "$DIRLIST_FILE"

    # Return the array via global variable
    declare -gA EXISTING_DIRLIST
    for key in "${!dirlist_array[@]}"; do
        EXISTING_DIRLIST["$key"]="${dirlist_array[$key]}"
    done

    return 0
}

# Create dialog checklist options
create_checklist_options() {
    local -a options=()

    # Combine discovered directories with existing dirlist
    local -A all_dirs

    # Add discovered directories
    for dir in "${DISCOVERED_DIRS[@]}"; do
        all_dirs["$dir"]="true"  # Default to discovered
    done

    # Override with existing settings if available
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        all_dirs["$dir"]="${EXISTING_DIRLIST[$dir]}"
    done

    # Create options array for dialog
    for dir in $(printf '%s\n' "${!all_dirs[@]}" | sort); do
        local status="${all_dirs[$dir]}"
        local check_status="off"

        if [[ "$status" == "true" ]]; then
            check_status="on"
        fi

        # Add directory to options: tag description status
        options+=("$dir" "Docker compose directory" "$check_status")
    done

    # Return options via global variable
    CHECKLIST_OPTIONS=("${options[@]}")
}

# Show main dialog interface
show_main_dialog() {
    local temp_file
    temp_file="$(mktemp)"

    # Create the checklist dialog
    if dialog --clear \
        --title "Backup Directory Management" \
        --backtitle "Docker Backup Script - Directory List Manager" \
        --checklist "Select directories to include in backup:\n\nUse SPACE to toggle, ENTER to confirm, ESC to cancel" \
        20 70 10 \
        "${CHECKLIST_OPTIONS[@]}" \
        2>"$temp_file"; then

        # User confirmed selection
        local selected_dirs
        selected_dirs="$(cat "$temp_file")"
        rm -f "$temp_file"

        # Process selected directories
        process_selection "$selected_dirs"
    else
        # User cancelled
        rm -f "$temp_file"
        print_info "Operation cancelled by user"
        exit $EXIT_USER_CANCEL
    fi
}

# Process user selection and show confirmation
process_selection() {
    local selected_dirs="$1"
    local -A new_settings
    local changes_made=false

    # Initialize all directories as false
    for dir in "${!EXISTING_DIRLIST[@]}" "${DISCOVERED_DIRS[@]}"; do
        new_settings["$dir"]="false"
    done

    # Set selected directories to true
    if [[ -n "$selected_dirs" ]]; then
        # Parse selected directories (space-separated, quoted)
        eval "selected_array=($selected_dirs)"
        for dir in "${selected_array[@]}"; do
            new_settings["$dir"]="true"
        done
    fi

    # Check for changes
    for dir in "${!new_settings[@]}"; do
        local old_setting="${EXISTING_DIRLIST[$dir]:-false}"
        local new_setting="${new_settings[$dir]}"

        if [[ "$old_setting" != "$new_setting" ]]; then
            changes_made=true
            break
        fi
    done

    # Show confirmation dialog
    show_confirmation_dialog new_settings "$changes_made"
}

# Show confirmation dialog with changes summary
show_confirmation_dialog() {
    local -n settings_ref=$1
    local changes_made="$2"
    local temp_file
    temp_file="$(mktemp)"

    # Create summary text
    local summary_text=""
    local enabled_count=0
    local disabled_count=0

    summary_text="Directory Backup Settings Summary:\n\n"
    summary_text+="ENABLED directories (will be backed up):\n"

    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        if [[ "${settings_ref[$dir]}" == "true" ]]; then
            summary_text+="  ✓ $dir\n"
            ((enabled_count++))
        fi
    done

    if [[ $enabled_count -eq 0 ]]; then
        summary_text+="  (none)\n"
    fi

    summary_text+="\nDISABLED directories (will be skipped):\n"

    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        if [[ "${settings_ref[$dir]}" == "false" ]]; then
            summary_text+="  ✗ $dir\n"
            ((disabled_count++))
        fi
    done

    if [[ $disabled_count -eq 0 ]]; then
        summary_text+="  (none)\n"
    fi

    summary_text+="\nTotal: $enabled_count enabled, $disabled_count disabled\n"

    if [[ "$changes_made" == "true" ]]; then
        summary_text+="\n⚠ Changes detected - .dirlist file will be updated"
    else
        summary_text+="\n✓ No changes made"
    fi

    # Show confirmation dialog
    if dialog --clear \
        --title "Confirm Changes" \
        --backtitle "Docker Backup Script - Directory List Manager" \
        --yesno "$summary_text\n\nDo you want to save these settings?" \
        25 80; then

        # User confirmed, save changes
        save_dirlist settings_ref
    else
        # User cancelled
        print_info "Changes not saved - operation cancelled"
        exit $EXIT_USER_CANCEL
    fi
}

# Save the new dirlist file (with locking)
save_dirlist() {
    local -n settings_ref=$1
    local temp_dirlist
    temp_dirlist="$(mktemp)"

    # Acquire lock before modifying dirlist
    if ! acquire_dirlist_lock 30; then
        rm -f "$temp_dirlist"
        print_error "Cannot save: failed to acquire lock"
        exit $EXIT_LOCK_ERROR
    fi

    print_info "Saving directory list to: $DIRLIST_FILE"

    # Write header
    cat > "$temp_dirlist" << 'EOF'
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup
EOF

    # Write directory settings in sorted order with validation
    local validation_errors=0
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        # Validate directory name before writing
        if validate_dir_name "$dir"; then
            echo "$dir=${settings_ref[$dir]}" >> "$temp_dirlist"
        else
            print_warning "Skipping invalid directory name: $dir"
            ((validation_errors++))
        fi
    done

    if [[ $validation_errors -gt 0 ]]; then
        print_warning "Skipped $validation_errors invalid directory name(s)"
    fi

    # Replace the dirlist file atomically
    if mv "$temp_dirlist" "$DIRLIST_FILE"; then
        # Set restrictive permissions
        chmod 600 "$DIRLIST_FILE" 2>/dev/null || true

        print_success "Directory list updated successfully!"
        print_info "File saved: $DIRLIST_FILE"

        # Show final summary
        local enabled_dirs=()
        for dir in "${!settings_ref[@]}"; do
            if [[ "${settings_ref[$dir]}" == "true" ]]; then
                enabled_dirs+=("$dir")
            fi
        done

        if [[ ${#enabled_dirs[@]} -gt 0 ]]; then
            print_info "Directories enabled for backup:"
            for dir in $(printf '%s\n' "${enabled_dirs[@]}" | sort); do
                echo "  ✓ $dir"
            done
        else
            print_warning "No directories are currently enabled for backup"
        fi
    else
        rm -f "$temp_dirlist"
        release_dirlist_lock
        print_error "Failed to save directory list file"
        exit $EXIT_CONFIG_ERROR
    fi

    # Release lock after save
    release_dirlist_lock
}

# Compare discovered directories with existing dirlist and identify changes
analyze_directory_changes() {
    local -a removed_dirs=()
    local -a new_dirs=()
    local changes_detected=false

    # Check for removed directories (in dirlist but not discovered)
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        local found=false
        for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
            if [[ "$dir" == "$discovered_dir" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            removed_dirs+=("$dir")
            changes_detected=true
        fi
    done

    # Check for new directories (discovered but not in dirlist)
    for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
        if [[ -z "${EXISTING_DIRLIST[$discovered_dir]:-}" ]]; then
            new_dirs+=("$discovered_dir")
            changes_detected=true
        fi
    done

    # Store results in global variables
    REMOVED_DIRS=("${removed_dirs[@]}")
    NEW_DIRS=("${new_dirs[@]}")
    CHANGES_DETECTED="$changes_detected"
}

# Apply automatic pruning changes to dirlist
apply_pruning_changes() {
    local -A updated_dirlist

    # Start with existing dirlist, excluding removed directories
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        local is_removed=false
        for removed_dir in "${REMOVED_DIRS[@]}"; do
            if [[ "$dir" == "$removed_dir" ]]; then
                is_removed=true
                break
            fi
        done
        if [[ "$is_removed" == "false" ]]; then
            updated_dirlist["$dir"]="${EXISTING_DIRLIST[$dir]}"
        fi
    done

    # Add new directories (defaulting to false for safety)
    for new_dir in "${NEW_DIRS[@]}"; do
        updated_dirlist["$new_dir"]="false"
    done

    # Update the global EXISTING_DIRLIST
    unset EXISTING_DIRLIST
    declare -gA EXISTING_DIRLIST
    for dir in "${!updated_dirlist[@]}"; do
        EXISTING_DIRLIST["$dir"]="${updated_dirlist[$dir]}"
    done
}

# Show changes summary
show_changes_summary() {
    local removed_count=${#REMOVED_DIRS[@]}
    local new_count=${#NEW_DIRS[@]}

    print_info "Directory synchronization summary:"

    if [[ $removed_count -gt 0 ]]; then
        print_warning "Removed directories (no longer exist):"
        for dir in "${REMOVED_DIRS[@]}"; do
            echo "  ✗ $dir"
        done
    fi

    if [[ $new_count -gt 0 ]]; then
        print_success "Added directories (defaulted to disabled):"
        for dir in "${NEW_DIRS[@]}"; do
            echo "  + $dir (enabled=false)"
        done
    fi

    if [[ $removed_count -eq 0 && $new_count -eq 0 ]]; then
        print_success "No changes needed - dirlist is already synchronized"
    else
        print_info "Total changes: $removed_count removed, $new_count added"
    fi
}

# Perform automatic pruning and synchronization
perform_pruning() {
    print_info "Performing automatic directory synchronization..."

    # Analyze changes
    analyze_directory_changes

    if [[ "$CHANGES_DETECTED" == "false" ]]; then
        print_success "Directory list is already synchronized with backup directory"
        return 0
    fi

    # Show what changes will be made
    show_changes_summary

    # Apply changes
    apply_pruning_changes

    # Save the updated dirlist
    save_dirlist EXISTING_DIRLIST

    print_success "Directory list has been synchronized successfully!"
    return 0
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Interactive TUI for managing Docker backup directory selection.

This script provides a dialog-based interface to:
- View all available Docker compose directories
- Enable/disable directories for backup
- Save changes to the .dirlist file
- Automatically synchronize dirlist with actual directories

OPTIONS:
    -h, --help      Show this help message
    -p, --prune     Automatically synchronize dirlist before showing interface
    --prune-only    Only perform synchronization, skip interactive interface

REQUIREMENTS:
- dialog command must be installed
- backup.conf must exist with valid BACKUP_DIR
- Must be run from the backup script directory

EXAMPLES:
    $SCRIPT_NAME                    # Run interactive interface
    $SCRIPT_NAME --prune           # Synchronize then run interface
    $SCRIPT_NAME --prune-only      # Only synchronize, no interface
    $SCRIPT_NAME --help            # Show this help

The script will automatically discover Docker compose directories
and allow you to select which ones should be included in backups.

SYNCHRONIZATION FEATURES:
- Removes entries for directories that no longer exist
- Adds entries for new directories (defaulted to disabled for safety)
- Shows summary of changes made during synchronization

EOF
}

#######################################
# Main Function
#######################################

main() {
    local prune_mode=false
    local prune_only=false

    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -p|--prune)
            prune_mode=true
            ;;
        --prune-only)
            prune_only=true
            ;;
        "")
            # No arguments, proceed with normal operation
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit $EXIT_CONFIG_ERROR
            ;;
    esac

    # Check prerequisites (only check dialog if we need interactive mode)
    if [[ "$prune_only" == "false" ]]; then
        check_dialog
    fi

    # Load configuration
    load_config

    # Discover directories
    declare -a DISCOVERED_DIRS
    declare -a REMOVED_DIRS
    declare -a NEW_DIRS
    declare CHANGES_DETECTED
    discover_directories

    if [[ ${#DISCOVERED_DIRS[@]} -eq 0 ]]; then
        print_warning "No Docker compose directories found in: $BACKUP_DIR"
        print_info "Make sure your Docker compose files are named:"
        print_info "  - docker-compose.yml"
        print_info "  - docker-compose.yaml"
        print_info "  - compose.yml"
        print_info "  - compose.yaml"
        exit $EXIT_SUCCESS
    fi

    # Load existing dirlist
    declare -A EXISTING_DIRLIST
    load_dirlist || true  # Don't fail if file doesn't exist

    # Perform pruning if requested
    if [[ "$prune_mode" == "true" || "$prune_only" == "true" ]]; then
        perform_pruning

        # If prune-only mode, exit after pruning
        if [[ "$prune_only" == "true" ]]; then
            exit $EXIT_SUCCESS
        fi

        # Add a separator before showing the interactive interface
        echo
        print_info "Proceeding to interactive directory selection..."
        echo
    fi

    # Create checklist options
    declare -a CHECKLIST_OPTIONS
    create_checklist_options

    # Show main dialog
    show_main_dialog
}

# Run main function with all arguments
main "$@"
