#!/bin/bash

# Test version of Directory List Management TUI Script
# This version shows discovery results without launching dialog

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

# Load configuration to get BACKUP_DIR
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Read configuration file and extract BACKUP_DIR
    local config_content
    config_content="$(grep -v '^[[:space:]]*#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | head -20)"
    
    if [[ -z "$config_content" ]]; then
        print_error "No valid configuration found in: $CONFIG_FILE"
        exit 1
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
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "Backup directory does not exist: $BACKUP_DIR"
        exit 1
    fi
    
    print_info "Using backup directory: $BACKUP_DIR"
}

# Discover Docker compose directories
discover_directories() {
    local found_dirs=()
    local dir_count=0
    
    print_info "Scanning for Docker compose directories in: $BACKUP_DIR"
    
    # Find all top-level subdirectories containing docker-compose files
    print_info "Debug: Running find command on: $BACKUP_DIR"
    while IFS= read -r -d '' dir; do
        local dir_name
        dir_name="$(basename "$dir")"
        print_info "Debug: Checking directory: $dir (basename: $dir_name)"
        
        # Skip hidden directories
        if [[ "$dir_name" =~ ^\..*$ ]]; then
            print_info "Debug: Skipping hidden directory: $dir_name"
            continue
        fi
        
        # Check if directory contains docker-compose files
        print_info "Debug: Looking for compose files in: $dir"
        if [[ -f "$dir/docker-compose.yml" ]]; then
            print_info "Debug: Found docker-compose.yml in $dir"
        fi
        if [[ -f "$dir/docker-compose.yaml" ]]; then
            print_info "Debug: Found docker-compose.yaml in $dir"
        fi
        if [[ -f "$dir/compose.yml" ]]; then
            print_info "Debug: Found compose.yml in $dir"
        fi
        if [[ -f "$dir/compose.yaml" ]]; then
            print_info "Debug: Found compose.yaml in $dir"
        fi
        
        if [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]] || [[ -f "$dir/compose.yml" ]] || [[ -f "$dir/compose.yaml" ]]; then
            found_dirs+=("$dir_name")
            ((dir_count++))
            print_info "  Found: $dir_name"
        else
            print_info "Debug: No compose files found in $dir"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -not -path "$BACKUP_DIR" -print0 2>/dev/null || true)
    
    print_success "Found $dir_count Docker compose directories"
    
    # Return the array via global variable
    DISCOVERED_DIRS=("${found_dirs[@]}")
}

# Load existing .dirlist file
load_dirlist() {
    local -A dirlist_array
    
    if [[ ! -f "$DIRLIST_FILE" ]]; then
        print_warning "Directory list file not found: $DIRLIST_FILE"
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
            print_info "  Loaded: $dir_name=$enabled"
        fi
    done < "$DIRLIST_FILE"
    
    # Return the array via global variable
    declare -gA EXISTING_DIRLIST
    for key in "${!dirlist_array[@]}"; do
        EXISTING_DIRLIST["$key"]="${dirlist_array[$key]}"
    done
    
    return 0
}

# Main test function
main() {
    print_info "=== Testing Directory List Management Script ==="
    
    # Load configuration
    load_config
    
    # Discover directories
    declare -a DISCOVERED_DIRS
    discover_directories
    
    if [[ ${#DISCOVERED_DIRS[@]} -eq 0 ]]; then
        print_warning "No Docker compose directories found in: $BACKUP_DIR"
        exit 0
    fi
    
    # Load existing dirlist
    declare -A EXISTING_DIRLIST
    if load_dirlist; then
        print_success "Existing .dirlist file loaded successfully"
    else
        print_info "No existing .dirlist file found - would create new one"
    fi
    
    # Show summary
    print_info "=== Summary ==="
    print_info "Discovered directories: ${#DISCOVERED_DIRS[@]}"
    for dir in "${DISCOVERED_DIRS[@]}"; do
        local status="${EXISTING_DIRLIST[$dir]:-"new (would default to false)"}"
        print_info "  $dir: $status"
    done
    
    print_success "Test completed successfully!"
    print_info "The full script would now show a dialog interface for managing these directories."
}

# Run main function
main "$@"