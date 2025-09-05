#!/bin/bash

# Directory List Management TUI Script
# Interactive dialog-based interface for managing .dirlist file
# Author: Generated for backup script management
# Version: 1.0

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/backup.conf}"
readonly DIRLIST_FILE="$SCRIPT_DIR/.dirlist"

# Default configuration
BACKUP_DIR=""

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
readonly EXIT_DIALOG_ERROR=2
readonly EXIT_USER_CANCEL=3

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
    
    # Find all top-level subdirectories containing docker-compose files
    while IFS= read -r -d '' dir; do
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
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -not -path "$BACKUP_DIR" -print0 2>/dev/null || true)
    
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
        clear
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
        clear
        print_info "Changes not saved - operation cancelled"
        exit $EXIT_USER_CANCEL
    fi
}

# Save the new dirlist file
save_dirlist() {
    local -n settings_ref=$1
    local temp_dirlist
    temp_dirlist="$(mktemp)"
    
    print_info "Saving directory list to: $DIRLIST_FILE"
    
    # Write header
    cat > "$temp_dirlist" << 'EOF'
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup
EOF
    
    # Write directory settings in sorted order
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        echo "$dir=${settings_ref[$dir]}" >> "$temp_dirlist"
    done
    
    # Replace the dirlist file
    if mv "$temp_dirlist" "$DIRLIST_FILE"; then
        clear
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
        print_error "Failed to save directory list file"
        exit $EXIT_CONFIG_ERROR
    fi
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

OPTIONS:
    -h, --help      Show this help message

REQUIREMENTS:
- dialog command must be installed
- backup.conf must exist with valid BACKUP_DIR
- Must be run from the backup script directory

EXAMPLES:
    $SCRIPT_NAME                    # Run interactive interface
    $SCRIPT_NAME --help            # Show this help

The script will automatically discover Docker compose directories
and allow you to select which ones should be included in backups.

EOF
}

#######################################
# Main Function
#######################################

main() {
    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
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
    
    # Check prerequisites
    check_dialog
    
    # Load configuration
    load_config
    
    # Discover directories
    declare -a DISCOVERED_DIRS
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
    
    # Create checklist options
    declare -a CHECKLIST_OPTIONS
    create_checklist_options
    
    # Show main dialog
    show_main_dialog
}

# Run main function with all arguments
main "$@"