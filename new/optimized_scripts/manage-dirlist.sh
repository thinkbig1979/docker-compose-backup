#!/bin/bash

# Directory List Management TUI Script - Format Fixed Version
# Interactive dialog-based interface for managing dirlist file
# Author: Optimized version with enhanced functionality
# Version: 2.1 - Fixed to handle actual dirlist format

# Bash error handling (strict mode removed for TUI compatibility)
# Note: Selective error handling added where most critical

# Script configuration constants
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
CONFIG_FILE="${BACKUP_CONFIG:-${SCRIPT_DIR}/backup.conf}"
readonly CONFIG_FILE
# Fixed: Use actual dirlist file location (same directory as script, no dot prefix)
readonly DIRLIST_FILE="${SCRIPT_DIR}/dirlist"

# Global variables
BACKUP_DIR=""
declare -a DISCOVERED_DIRS=()
declare -A EXISTING_DIRLIST=()
declare -a CHECKLIST_OPTIONS=()
declare -a REMOVED_DIRS=()
declare -a NEW_DIRS=()
CHANGES_DETECTED="false"

# Store non-directory lines from dirlist (paths and comments) to preserve them
declare -a DIRLIST_HEADER_LINES=()

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

# Temporary files array for cleanup
declare -a TEMP_FILES=()

####
# Cleanup and Error Handling
####

# Terminal cleanup function
cleanup_terminal() {
    # Clear dialog artifacts and restore terminal
    clear 2>/dev/null || true
    # Reset terminal to normal state
    tput sgr0 2>/dev/null || true
    # Show cursor if it was hidden
    tput cnorm 2>/dev/null || true
    # Clean up temporary files
    cleanup_temp_files
}

# Clean up temporary files
cleanup_temp_files() {
    local temp_file
    for temp_file in "${TEMP_FILES[@]}"; do
        [[ -f "${temp_file}" ]] && rm -f "${temp_file}"
    done
    TEMP_FILES=()
}

# Create temporary file and track it for cleanup
create_temp_file() {
    local temp_file
    temp_file="$(mktemp)"
    TEMP_FILES+=("${temp_file}")
    echo "${temp_file}"
}

# Error handler function
error_handler() {
    local line_no="$1"
    local error_code="$2"
    print_error "Script failed at line ${line_no} with exit code ${error_code}"
    cleanup_terminal
    exit "${error_code}"
}

# Set up traps for cleanup (error trap removed for TUI compatibility)
trap cleanup_terminal EXIT

####
# Utility Functions
####

# Print colored output with consistent formatting
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

print_debug() {
    [[ "${DEBUG:-}" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2
}

# Check if we're in a proper terminal environment
check_terminal() {
    # Only check for interactive terminal if we need dialog interface
    local need_interactive="${1:-true}"
    
    if [[ "${need_interactive}" == "true" ]]; then
        # Check if we have a terminal
        if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
            print_error "This script requires an interactive terminal for TUI mode"
            print_error "Use --prune-only for non-interactive operation"
            exit "${EXIT_DIALOG_ERROR}"
        fi
    fi
    
    # Set TERM if not set (common in some SSH environments)
    if [[ -z "${TERM:-}" ]]; then
        export TERM="xterm"
        print_debug "TERM not set, defaulting to xterm"
    fi
}

# Check if dialog command is available and working
check_dialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        print_error "The 'dialog' command is not installed or not in PATH"
        print_error "Please install dialog package:"
        print_error "  Ubuntu/Debian: sudo apt-get install dialog"
        print_error "  CentOS/RHEL: sudo yum install dialog"
        print_error "  Fedora: sudo dnf install dialog"
        exit "${EXIT_DIALOG_ERROR}"
    fi
    
    # Test dialog functionality
    if ! dialog --version >/dev/null 2>&1; then
        print_error "Dialog command is installed but not functioning properly"
        exit "${EXIT_DIALOG_ERROR}"
    fi
}

# Validate directory path
validate_directory() {
    local dir_path="$1"
    local dir_name="$2"
    
    if [[ -z "${dir_path}" ]]; then
        print_error "${dir_name} is not configured"
        return 1
    fi
    
    if [[ ! -d "${dir_path}" ]]; then
        print_error "${dir_name} does not exist: ${dir_path}"
        return 1
    fi
    
    if [[ ! -r "${dir_path}" ]]; then
        print_error "${dir_name} is not readable: ${dir_path}"
        return 1
    fi
    
    return 0
}

####
# Configuration Management
####

# Load and validate configuration
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        print_error "Configuration file not found: ${CONFIG_FILE}"
        print_error "Please ensure backup.conf exists in the script directory"
        exit "${EXIT_CONFIG_ERROR}"
    fi
    
    if [[ ! -r "${CONFIG_FILE}" ]]; then
        print_error "Configuration file is not readable: ${CONFIG_FILE}"
        exit "${EXIT_CONFIG_ERROR}"
    fi
    
    print_debug "Loading configuration from: ${CONFIG_FILE}"
    
    # Read configuration file safely
    local config_content
    config_content="$(grep -v '^[[:space:]]*#' "${CONFIG_FILE}" | grep -v '^[[:space:]]*$' || true)"
    
    if [[ -z "${config_content}" ]]; then
        print_error "No valid configuration found in: ${CONFIG_FILE}"
        exit "${EXIT_CONFIG_ERROR}"
    fi
    
    # Parse BACKUP_DIR from configuration
    local key value line
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -n "${line}" ]] || continue
        [[ ! "${line}" =~ ^[[:space:]]*# ]] || continue
        
        # Parse key=value
        if [[ "${line}" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Strip whitespace from key
            key="$(echo "${key}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            # Strip inline comments and whitespace from value
            value="$(echo "${value}" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            
            if [[ "${key}" == "BACKUP_DIR" ]]; then
                # Remove quotes if present
                BACKUP_DIR="${value%\"}"
                BACKUP_DIR="${BACKUP_DIR#\"}"
                BACKUP_DIR="${BACKUP_DIR%\'}"
                BACKUP_DIR="${BACKUP_DIR#\'}"
                break
            fi
        fi
    done < "${CONFIG_FILE}"
    
    # Validate BACKUP_DIR
    if [[ -z "${BACKUP_DIR}" ]]; then
        print_error "BACKUP_DIR not found in configuration file"
        exit "${EXIT_CONFIG_ERROR}"
    fi
    
    if ! validate_directory "${BACKUP_DIR}" "Backup directory"; then
        exit "${EXIT_CONFIG_ERROR}"
    fi
    
    print_info "Using backup directory: ${BACKUP_DIR}"
}

####
# Directory Discovery and Management
####

# Check if directory contains Docker compose files
has_compose_files() {
    local dir_path="$1"
    
    [[ -f "${dir_path}/docker-compose.yml" ]] || \
    [[ -f "${dir_path}/docker-compose.yaml" ]] || \
    [[ -f "${dir_path}/compose.yml" ]] || \
    [[ -f "${dir_path}/compose.yaml" ]]
}

# Discover Docker compose directories
discover_directories() {
    local -a found_dirs=()
    local dir_count=0
    
    print_info "Scanning for Docker compose directories in: ${BACKUP_DIR}"
    
    # Find all top-level subdirectories containing docker-compose files
    # Use a simpler approach with for loop to avoid process substitution issues
    print_debug "Starting directory scan loop..."
    local dir
    for dir in "${BACKUP_DIR}"/*; do
        print_debug "Processing: ${dir}"
        # Skip if not a directory
        if [[ ! -d "${dir}" ]]; then
            print_debug "  Skipping (not a directory)"
            continue
        fi
        
        local dir_name
        dir_name="$(basename "${dir}")"
        print_debug "  Directory name: ${dir_name}"
        
        # Skip hidden directories
        if [[ "${dir_name}" =~ ^\..*$ ]]; then
            print_debug "  Skipping (hidden directory)"
            continue
        fi
        
        # Check if directory contains docker-compose files
        print_debug "  Checking for compose files..."
        local has_compose=false
        
        if [[ -f "${dir}/docker-compose.yml" ]]; then
            print_debug "    Found docker-compose.yml"
            has_compose=true
        elif [[ -f "${dir}/docker-compose.yaml" ]]; then
            print_debug "    Found docker-compose.yaml"
            has_compose=true
        elif [[ -f "${dir}/compose.yml" ]]; then
            print_debug "    Found compose.yml"
            has_compose=true
        elif [[ -f "${dir}/compose.yaml" ]]; then
            print_debug "    Found compose.yaml"
            has_compose=true
        fi
        
        if [[ "${has_compose}" == "true" ]]; then
            found_dirs+=("${dir_name}")
            dir_count=$((dir_count + 1))
            print_debug "  Added compose directory: ${dir_name} (count: ${dir_count})"
        else
            print_debug "  No compose files found"
        fi
    done
    print_debug "Directory scan loop completed"
    
    print_info "Found ${dir_count} Docker compose directories"
    print_debug "Directory discovery completed"
    
    # Update global array
    DISCOVERED_DIRS=("${found_dirs[@]}")
    print_debug "Global array updated with ${#DISCOVERED_DIRS[@]} directories"
}

# Load existing dirlist file - FIXED to handle actual format
load_dirlist() {
    local -A dirlist_array=()
    local -a header_lines=()
    
    if [[ ! -f "${DIRLIST_FILE}" ]]; then
        print_warning "Directory list file not found: ${DIRLIST_FILE}"
        print_info "Will create new dirlist file based on discovered directories"
        return 1
    fi
    
    if [[ ! -r "${DIRLIST_FILE}" ]]; then
        print_error "Directory list file is not readable: ${DIRLIST_FILE}"
        return 1
    fi
    
    print_info "Loading existing directory list from: ${DIRLIST_FILE}"
    
    # Read the dirlist file and populate the associative array
    local dir_name enabled line_count=0 loaded_count=0 line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_count++))
        print_debug "Processing line ${line_count}: '${line}'"
        
        # Check if this is a path line (starts with /)
        if [[ "${line}" =~ ^/ ]]; then
            header_lines+=("${line}")
            print_debug "  Saved as header line (path): ${line}"
            continue
        fi
        
        # Check if this is a comment line (starts with #)
        if [[ "${line}" =~ ^[[:space:]]*# ]] || [[ -z "${line// /}" ]]; then
            header_lines+=("${line}")
            print_debug "  Saved as header line (comment/empty): ${line}"
            continue
        fi
        
        # Try to parse as key=value
        if [[ "${line}" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            dir_name="${BASH_REMATCH[1]}"
            enabled="${BASH_REMATCH[2]}"
            
            # Clean up whitespace
            dir_name="$(echo "${dir_name}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            enabled="$(echo "${enabled}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            
            # Validate format
            if [[ "${enabled}" =~ ^(true|false)$ ]] && [[ -n "${dir_name}" ]]; then
                dirlist_array["${dir_name}"]="${enabled}"
                ((loaded_count++))
                print_debug "  Loaded directory setting: ${dir_name}=${enabled}"
            else
                print_debug "  Invalid key=value format, saving as header line: ${line}"
                header_lines+=("${line}")
            fi
        else
            print_debug "  Not key=value format, saving as header line: ${line}"
            header_lines+=("${line}")
        fi
    done < "${DIRLIST_FILE}"
    
    print_debug "Processed ${line_count} lines, loaded ${loaded_count} directory entries"
    print_debug "Saved ${#header_lines[@]} header lines"
    
    # Update global associative array and header lines
    EXISTING_DIRLIST=()
    local key
    for key in "${!dirlist_array[@]}"; do
        EXISTING_DIRLIST["${key}"]="${dirlist_array[${key}]}"
    done
    
    DIRLIST_HEADER_LINES=("${header_lines[@]}")
    
    print_debug "Updated global EXISTING_DIRLIST with ${#EXISTING_DIRLIST[@]} entries"
    print_debug "Updated global DIRLIST_HEADER_LINES with ${#DIRLIST_HEADER_LINES[@]} lines"
    return 0
}

####
# Directory Change Analysis and Pruning
####

# Compare discovered directories with existing dirlist and identify changes
analyze_directory_changes() {
    local -a removed_dirs=()
    local -a new_dirs=()
    local changes_detected="false"
    
    print_debug "Analyzing directory changes..."
    
    # Check for removed directories (in dirlist but not discovered)
    local dir found
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        found="false"
        local discovered_dir
        for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
            if [[ "${dir}" == "${discovered_dir}" ]]; then
                found="true"
                break
            fi
        done
        if [[ "${found}" == "false" ]]; then
            removed_dirs+=("${dir}")
            changes_detected="true"
            print_debug "Directory removed: ${dir}"
        fi
    done
    
    # Check for new directories (discovered but not in dirlist)
    for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
        if [[ -z "${EXISTING_DIRLIST[${discovered_dir}]:-}" ]]; then
            new_dirs+=("${discovered_dir}")
            changes_detected="true"
            print_debug "New directory found: ${discovered_dir}"
        fi
    done
    
    # Update global variables
    REMOVED_DIRS=("${removed_dirs[@]}")
    NEW_DIRS=("${new_dirs[@]}")
    CHANGES_DETECTED="${changes_detected}"
}

# Apply automatic pruning changes to dirlist
apply_pruning_changes() {
    local -A updated_dirlist=()
    
    print_debug "Applying pruning changes..."
    
    # Start with existing dirlist, excluding removed directories
    local dir is_removed removed_dir
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        is_removed="false"
        for removed_dir in "${REMOVED_DIRS[@]}"; do
            if [[ "${dir}" == "${removed_dir}" ]]; then
                is_removed="true"
                break
            fi
        done
        if [[ "${is_removed}" == "false" ]]; then
            updated_dirlist["${dir}"]="${EXISTING_DIRLIST[${dir}]}"
        fi
    done
    
    # Add new directories (defaulting to false for safety)
    local new_dir
    for new_dir in "${NEW_DIRS[@]}"; do
        updated_dirlist["${new_dir}"]="false"
    done
    
    # Update the global EXISTING_DIRLIST
    EXISTING_DIRLIST=()
    for dir in "${!updated_dirlist[@]}"; do
        EXISTING_DIRLIST["${dir}"]="${updated_dirlist[${dir}]}"
    done
}

# Show changes summary
show_changes_summary() {
    local removed_count="${#REMOVED_DIRS[@]}"
    local new_count="${#NEW_DIRS[@]}"
    
    print_info "Directory synchronization summary:"
    
    if [[ "${removed_count}" -gt 0 ]]; then
        print_warning "Removed directories (no longer exist):"
        local dir
        for dir in "${REMOVED_DIRS[@]}"; do
            echo "  ✗ ${dir}"
        done
    fi
    
    if [[ "${new_count}" -gt 0 ]]; then
        print_success "Added directories (defaulted to disabled):"
        local dir
        for dir in "${NEW_DIRS[@]}"; do
            echo "  + ${dir} (enabled=false)"
        done
    fi
    
    if [[ "${removed_count}" -eq 0 && "${new_count}" -eq 0 ]]; then
        print_success "Directory list is already synchronized with backup directory"
    else
        print_info "Total changes: ${removed_count} removed, ${new_count} added"
    fi
}

# Perform automatic pruning and synchronization
perform_pruning() {
    print_info "Performing automatic directory synchronization..."
    
    # Analyze changes
    analyze_directory_changes
    
    if [[ "${CHANGES_DETECTED}" == "false" ]]; then
        print_success "Directory list is already synchronized with backup directory"
        return 0
    fi
    
    # Show what changes will be made
    show_changes_summary
    
    # Apply changes
    apply_pruning_changes
    
    # Save the updated dirlist
    save_dirlist
    
    print_success "Directory list has been synchronized successfully!"
    return 0
}

####
# Dialog Interface Functions
####

# Create dialog checklist options
create_checklist_options() {
    local -a options=()
    local -A all_dirs=()
    
    print_debug "Creating checklist options..."
    
    # First, add all directories from existing dirlist with their current settings
    local dir
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        all_dirs["${dir}"]="${EXISTING_DIRLIST[${dir}]}"
        print_debug "Added from existing dirlist: ${dir}=${EXISTING_DIRLIST[${dir}]}"
    done
    
    # Then add any newly discovered directories that aren't in existing dirlist
    for dir in "${DISCOVERED_DIRS[@]}"; do
        if [[ -z "${all_dirs[${dir}]:-}" ]]; then
            all_dirs["${dir}"]="false"  # Default to disabled for safety
            print_debug "Added new discovered directory: ${dir}=false"
        fi
    done
    
    # Create options array for dialog
    local status check_status
    for dir in $(printf '%s\n' "${!all_dirs[@]}" | sort); do
        status="${all_dirs[${dir}]}"
        check_status="off"
        
        if [[ "${status}" == "true" ]]; then
            check_status="on"
        fi
        
        # Add directory to options: tag description status
        options+=("${dir}" "Docker compose directory" "${check_status}")
        print_debug "Dialog option: ${dir} -> ${check_status}"
    done
    
    # Update global array
    CHECKLIST_OPTIONS=("${options[@]}")
    print_debug "Created ${#CHECKLIST_OPTIONS[@]} checklist options"
}

# Show main menu dialog
show_main_menu() {
    local temp_file
    temp_file="$(create_temp_file)"
    
    local menu_text="Choose an action:\n\n"
    menu_text+="• Manage Directories: Select which directories to backup\n"
    menu_text+="• Prune & Sync: Automatically sync dirlist with filesystem\n"
    menu_text+="• View Status: Show current backup directory status\n"
    menu_text+="• Exit: Quit the application"
    
    if dialog --clear \
        --title "Backup Directory Management" \
        --backtitle "Docker Backup Script - Directory List Manager v2.1" \
        --menu "${menu_text}" \
        18 70 4 \
        "manage" "Manage backup directory selection" \
        "prune" "Prune & sync directories automatically" \
        "status" "View current directory status" \
        "exit" "Exit the application" \
        2>"${temp_file}"; then
        
        local choice
        choice="$(cat "${temp_file}")"
        
        case "${choice}" in
            "manage")
                show_directory_selection
                ;;
            "prune")
                perform_pruning_interactive
                ;;
            "status")
                show_status_dialog
                ;;
            "exit")
                print_info "Exiting application"
                exit "${EXIT_SUCCESS}"
                ;;
            *)
                print_error "Unknown choice: ${choice}"
                exit "${EXIT_CONFIG_ERROR}"
                ;;
        esac
    else
        # User cancelled
        print_info "Operation cancelled by user"
        exit "${EXIT_USER_CANCEL}"
    fi
}

# Show directory selection dialog
show_directory_selection() {
    local temp_file
    temp_file="$(create_temp_file)"
    
    # Create the checklist dialog
    if dialog --clear \
        --title "Backup Directory Selection" \
        --backtitle "Docker Backup Script - Directory List Manager v2.1" \
        --checklist "Select directories to include in backup:\n\nUse SPACE to toggle, ENTER to confirm, ESC to cancel" \
        20 70 10 \
        "${CHECKLIST_OPTIONS[@]}" \
        2>"${temp_file}"; then
        
        # User confirmed selection
        local selected_dirs
        selected_dirs="$(cat "${temp_file}")"
        
        # Process selected directories
        process_selection "${selected_dirs}"
    else
        # User cancelled, return to main menu
        show_main_menu
    fi
}

# Show status dialog
show_status_dialog() {
    local status_text=""
    local enabled_count=0
    local disabled_count=0
    local total_count="${#DISCOVERED_DIRS[@]}"
    
    status_text="Current Backup Directory Status:\n\n"
    status_text+="Backup Directory: ${BACKUP_DIR}\n"
    status_text+="Total Directories: ${total_count}\n\n"
    
    if [[ "${total_count}" -eq 0 ]]; then
        status_text+="No Docker compose directories found.\n"
    else
        status_text+="ENABLED directories (will be backed up):\n"
        
        local dir
        for dir in $(printf '%s\n' "${!EXISTING_DIRLIST[@]}" | sort); do
            if [[ "${EXISTING_DIRLIST[${dir}]}" == "true" ]]; then
                status_text+="  ✓ ${dir}\n"
                ((enabled_count++))
            fi
        done
        
        if [[ "${enabled_count}" -eq 0 ]]; then
            status_text+="  (none)\n"
        fi
        
        status_text+="\nDISABLED directories (will be skipped):\n"
        
        for dir in $(printf '%s\n' "${!EXISTING_DIRLIST[@]}" | sort); do
            if [[ "${EXISTING_DIRLIST[${dir}]}" == "false" ]]; then
                status_text+="  ✗ ${dir}\n"
                ((disabled_count++))
            fi
        done
        
        if [[ "${disabled_count}" -eq 0 ]]; then
            status_text+="  (none)\n"
        fi
        
        status_text+="\nSummary: ${enabled_count} enabled, ${disabled_count} disabled"
    fi
    
    dialog --clear \
        --title "Directory Status" \
        --backtitle "Docker Backup Script - Directory List Manager v2.1" \
        --msgbox "${status_text}" \
        20 70
    
    # Return to main menu
    show_main_menu
}

# Perform pruning with interactive feedback
perform_pruning_interactive() {
    # Show info dialog first
    dialog --clear \
        --title "Prune & Sync" \
        --backtitle "Docker Backup Script - Directory List Manager v2.1" \
        --infobox "Analyzing directories and synchronizing...\n\nPlease wait..." \
        6 50
    
    # Perform the actual pruning
    perform_pruning
    
    # Show completion dialog
    local result_text="Synchronization completed successfully!\n\n"
    result_text+="The directory list has been updated to match\n"
    result_text+="the current filesystem state.\n\n"
    result_text+="You can now manage individual directory\n"
    result_text+="settings if needed."
    
    dialog --clear \
        --title "Prune & Sync Complete" \
        --backtitle "Docker Backup Script - Directory List Manager v2.1" \
        --msgbox "${result_text}" \
        12 50
    
    # Reload dirlist and return to main menu
    load_dirlist || true
    create_checklist_options
    show_main_menu
}

# Process user selection and show confirmation
process_selection() {
    local selected_dirs="$1"
    local -A new_settings=()
    local changes_made="false"
    
    print_debug "Processing selection: ${selected_dirs}"
    
    # Initialize all directories as false
    local dir
    for dir in "${!EXISTING_DIRLIST[@]}" "${DISCOVERED_DIRS[@]}"; do
        new_settings["${dir}"]="false"
    done
    
    # Set selected directories to true
    if [[ -n "${selected_dirs}" ]]; then
        # Parse selected directories (space-separated, quoted)
        local -a selected_array
        eval "selected_array=(${selected_dirs})"
        for dir in "${selected_array[@]}"; do
            new_settings["${dir}"]="true"
        done
    fi
    
    # Check for changes
    for dir in "${!new_settings[@]}"; do
        local old_setting="${EXISTING_DIRLIST[${dir}]:-false}"
        local new_setting="${new_settings[${dir}]}"
        
        if [[ "${old_setting}" != "${new_setting}" ]]; then
            changes_made="true"
            break
        fi
    done
    
    # Show confirmation dialog
    show_confirmation_dialog new_settings "${changes_made}"
}

# Show confirmation dialog with changes summary
show_confirmation_dialog() {
    local -n settings_ref=$1
    local changes_made="$2"
    
    # Create summary text
    local summary_text=""
    local enabled_count=0
    local disabled_count=0
    
    summary_text="Directory Backup Settings Summary:\n\n"
    summary_text+="ENABLED directories (will be backed up):\n"
    
    local dir
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        if [[ "${settings_ref[${dir}]}" == "true" ]]; then
            summary_text+="  ✓ ${dir}\n"
            ((enabled_count++))
        fi
    done
    
    if [[ "${enabled_count}" -eq 0 ]]; then
        summary_text+="  (none)\n"
    fi
    
    summary_text+="\nDISABLED directories (will be skipped):\n"
    
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        if [[ "${settings_ref[${dir}]}" == "false" ]]; then
            summary_text+="  ✗ ${dir}\n"
            ((disabled_count++))
        fi
    done
    
    if [[ "${disabled_count}" -eq 0 ]]; then
        summary_text+="  (none)\n"
    fi
    
    summary_text+="\nTotal: ${enabled_count} enabled, ${disabled_count} disabled\n"
    
    if [[ "${changes_made}" == "true" ]]; then
        summary_text+="\n⚠ Changes detected - dirlist file will be updated"
    else
        summary_text+="\n✓ No changes made"
    fi
    
    # Show confirmation dialog
    if dialog --clear \
        --title "Confirm Changes" \
        --backtitle "Docker Backup Script - Directory List Manager v2.1" \
        --yesno "${summary_text}\n\nDo you want to save these settings?" \
        25 80; then
        
        # User confirmed, save changes
        save_dirlist_with_settings settings_ref
        
        # Show success and return to main menu
        dialog --clear \
            --title "Settings Saved" \
            --backtitle "Docker Backup Script - Directory List Manager v2.1" \
            --msgbox "Directory settings have been saved successfully!" \
            6 50
        
        # Update global settings and return to main menu
        local key
        for key in "${!settings_ref[@]}"; do
            EXISTING_DIRLIST["${key}"]="${settings_ref[${key}]}"
        done
        create_checklist_options
        show_main_menu
    else
        # User cancelled, return to directory selection
        show_directory_selection
    fi
}

####
# File Operations - FIXED to preserve exact format
####

# Save the dirlist file with current EXISTING_DIRLIST
save_dirlist() {
    save_dirlist_with_settings EXISTING_DIRLIST
}

# Save the new dirlist file with provided settings - FIXED to preserve format
save_dirlist_with_settings() {
    local -n settings_ref=$1
    local temp_dirlist
    temp_dirlist="$(create_temp_file)"
    
    print_info "Saving directory list to: ${DIRLIST_FILE}"
    
    # Write preserved header lines (paths and comments) first
    local header_line
    for header_line in "${DIRLIST_HEADER_LINES[@]}"; do
        echo "${header_line}" >> "${temp_dirlist}"
    done
    
    # Write directory settings in sorted order (key=value format)
    local dir
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        echo "${dir}=${settings_ref[${dir}]}" >> "${temp_dirlist}"
    done
    
    # Replace the dirlist file atomically
    if mv "${temp_dirlist}" "${DIRLIST_FILE}"; then
        print_success "Directory list updated successfully!"
        print_info "File saved: ${DIRLIST_FILE}"
        
        # Show final summary
        local -a enabled_dirs=()
        for dir in "${!settings_ref[@]}"; do
            if [[ "${settings_ref[${dir}]}" == "true" ]]; then
                enabled_dirs+=("${dir}")
            fi
        done
        
        if [[ "${#enabled_dirs[@]}" -gt 0 ]]; then
            print_info "Directories enabled for backup:"
            for dir in $(printf '%s\n' "${enabled_dirs[@]}" | sort); do
                echo "  ✓ ${dir}"
            done
        else
            print_warning "No directories are currently enabled for backup"
        fi
    else
        print_error "Failed to save directory list file"
        exit "${EXIT_CONFIG_ERROR}"
    fi
}

####
# Help and Usage
####

# Show usage information
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Interactive TUI for managing Docker backup directory selection.

This script provides a dialog-based interface to:
- View all available Docker compose directories
- Enable/disable directories for backup
- Save changes to the dirlist file
- Automatically synchronize dirlist with actual directories

OPTIONS:
    -h, --help       Show this help message
    -p, --prune      Automatically synchronize dirlist before showing interface
    --prune-only     Only perform synchronization, skip interactive interface
    --debug          Enable debug output

REQUIREMENTS:
- dialog command must be installed
- backup.conf must exist with valid BACKUP_DIR
- Must be run from the backup script directory

EXAMPLES:
    ${SCRIPT_NAME}                # Run interactive interface
    ${SCRIPT_NAME} --prune        # Synchronize then show interface
    ${SCRIPT_NAME} --prune-only   # Only synchronize, no interface
    DEBUG=true ${SCRIPT_NAME}     # Run with debug output

FILES:
    dirlist          Directory list file (same directory as script)
    backup.conf      Configuration file with BACKUP_DIR setting

NOTES:
- New directories are disabled by default for safety
- The dirlist format is preserved exactly for compatibility
- Removed directories are automatically pruned from the list
- All changes require user confirmation before saving

EOF
}

####
# Main Script Logic
####

# Parse command line arguments
parse_arguments() {
    local prune_before_ui="false"
    local prune_only="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit "${EXIT_SUCCESS}"
                ;;
            -p|--prune)
                prune_before_ui="true"
                shift
                ;;
            --prune-only)
                prune_only="true"
                shift
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                print_error "Use --help for usage information"
                exit "${EXIT_CONFIG_ERROR}"
                ;;
        esac
    done
    
    # Set global flags
    if [[ "${prune_only}" == "true" ]]; then
        PRUNE_ONLY="true"
        PRUNE_BEFORE_UI="false"
    else
        PRUNE_ONLY="false"
        PRUNE_BEFORE_UI="${prune_before_ui}"
    fi
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check terminal environment (skip for prune-only mode)
    if [[ "${PRUNE_ONLY:-false}" == "false" ]]; then
        check_terminal true
        check_dialog
    else
        check_terminal false
    fi
    
    print_info "Starting Directory List Manager v2.1"
    print_debug "Script directory: ${SCRIPT_DIR}"
    print_debug "Dirlist file: ${DIRLIST_FILE}"
    print_debug "Config file: ${CONFIG_FILE}"
    
    # Load configuration
    load_config
    
    # Discover directories
    discover_directories
    
    # Load existing dirlist
    load_dirlist || true
    
    # Perform pruning if requested or in prune-only mode
    if [[ "${PRUNE_BEFORE_UI:-false}" == "true" ]] || [[ "${PRUNE_ONLY:-false}" == "true" ]]; then
        perform_pruning
        
        # Exit if prune-only mode
        if [[ "${PRUNE_ONLY:-false}" == "true" ]]; then
            exit "${EXIT_SUCCESS}"
        fi
        
        # Reload dirlist after pruning
        load_dirlist || true
    fi
    
    # Create checklist options for dialog interface
    create_checklist_options
    
    # Show main menu
    show_main_menu
}

# Run main function with all arguments
main "$@"
