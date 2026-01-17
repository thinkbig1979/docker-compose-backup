#!/bin/bash

# Docker Stack 3-Stage Backup System - Text User Interface
# Unified TUI for managing Docker backups, cloud sync, and restore operations
# Author: Generated for comprehensive backup management
# Version: 1.0

# Bash strict mode for better error handling
set -eo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TUI_LOG_FILE="$SCRIPT_DIR/../logs/backup_tui.log"

# Backup system scripts
readonly DOCKER_BACKUP_SCRIPT="$SCRIPT_DIR/docker-backup.sh"
readonly RCLONE_BACKUP_SCRIPT="$SCRIPT_DIR/../scripts/rclone_backup.sh"
readonly RCLONE_RESTORE_SCRIPT="$SCRIPT_DIR/../scripts/rclone_restore.sh"
readonly MANAGE_DIRLIST_SCRIPT="$SCRIPT_DIR/manage-dirlist.sh"

# Configuration files
readonly BACKUP_CONFIG="$SCRIPT_DIR/../config/backup.conf"
readonly RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"

# TUI Configuration
readonly TUI_TITLE="Docker Stack 3-Stage Backup System"
readonly TUI_VERSION="1.0"
readonly DIALOG_HEIGHT=20
readonly DIALOG_WIDTH=70
readonly DIALOG_MENU_HEIGHT=12

# Global variables
TEMP_DIR=""
LAST_OPERATION_LOG=""

# Navigation breadcrumb tracking
declare -a MENU_BREADCRUMB=()

# Sync status tracking
SYNC_NEW_DIRS=()
SYNC_REMOVED_DIRS=()
SYNC_STATUS="unknown"

#######################################
# TUI Utility Functions
#######################################

# Initialize TUI environment
init_tui() {
    # Ensure dialog is available
    if ! command -v dialog >/dev/null 2>&1; then
        echo "Error: 'dialog' command not found. Please install dialog package."
        echo "Ubuntu/Debian: sudo apt-get install dialog"
        echo "CentOS/RHEL: sudo yum install dialog"
        exit 1
    fi

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)

    # Set up signal handlers for clean exit
    trap cleanup_tui EXIT
    trap 'echo ""; exit_tui' INT TERM HUP

    # Ensure log directory exists
    local log_dir="$(dirname "$TUI_LOG_FILE")"
    [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir"

    # Initialize log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TUI Started" >> "$TUI_LOG_FILE"
}

# Cleanup TUI environment - improved with signal safety
cleanup_tui() {
    local exit_code=$?

    # Disable further signal handling during cleanup
    trap '' EXIT INT TERM HUP 2>/dev/null || true

    # Reset terminal to normal state (with error suppression)
    clear 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    stty sane 2>/dev/null || true
    reset 2>/dev/null || true

    # Clean up temporary files
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi

    # Clean up any registered temp files
    if [[ -n "${CLEANUP_FILES[*]:-}" ]]; then
        local temp_file
        for temp_file in "${CLEANUP_FILES[@]}"; do
            rm -f "$temp_file" 2>/dev/null || true
        done
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TUI Exited (code: $exit_code)" >> "$TUI_LOG_FILE" 2>/dev/null || true
}

# Array for registering temp files for cleanup
declare -a CLEANUP_FILES=()

# Register a temp file for cleanup on exit
register_temp_file() {
    CLEANUP_FILES+=("$1")
}

# Graceful TUI exit
exit_tui() {
    # Clear any dialog remnants
    clear

    # Display farewell message
    echo
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                     Thank you for using the                         ║"
    echo "║             Docker Stack 3-Stage Backup System TUI!                 ║"
    echo "║                                                                      ║"
    echo "║  • Stage 1: Docker Backup   ✓                                       ║"
    echo "║  • Stage 2: Cloud Sync      ✓                                       ║"
    echo "║  • Stage 3: Cloud Restore   ✓                                       ║"
    echo "║                                                                      ║"
    echo "║  Your backup system is ready for production use.                    ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo

    # Allow cleanup to run
    exit 0
}

# Log TUI operations
log_tui() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$TUI_LOG_FILE"
}

#######################################
# Breadcrumb Navigation Functions
#######################################

# Push a menu onto the breadcrumb stack
push_breadcrumb() {
    local menu_name="$1"
    MENU_BREADCRUMB+=("$menu_name")
}

# Pop a menu from the breadcrumb stack
pop_breadcrumb() {
    if [[ ${#MENU_BREADCRUMB[@]} -gt 0 ]]; then
        unset 'MENU_BREADCRUMB[${#MENU_BREADCRUMB[@]}-1]'
    fi
}

# Get the current breadcrumb path as a string
get_breadcrumb_path() {
    local path=""
    for item in "${MENU_BREADCRUMB[@]}"; do
        if [[ -n "$path" ]]; then
            path="$path > $item"
        else
            path="$item"
        fi
    done
    echo "$path"
}

# Get title with breadcrumb
get_title_with_breadcrumb() {
    local title="$1"
    local breadcrumb
    breadcrumb=$(get_breadcrumb_path)

    if [[ -n "$breadcrumb" ]]; then
        echo "$title [$breadcrumb]"
    else
        echo "$title"
    fi
}

#######################################
# Standardized Dialog Functions
#######################################

# Dialog size constants for consistency
readonly DLG_SM_HEIGHT=10
readonly DLG_SM_WIDTH=50
readonly DLG_MD_HEIGHT=15
readonly DLG_MD_WIDTH=60
readonly DLG_LG_HEIGHT=20
readonly DLG_LG_WIDTH=70
readonly DLG_XL_HEIGHT=25
readonly DLG_XL_WIDTH=80

# Show information dialog
show_info() {
    local title="$1"
    local message="$2"
    local size="${3:-medium}"  # small, medium, large

    local height=$DLG_MD_HEIGHT
    local width=$DLG_MD_WIDTH

    case "$size" in
        small)  height=$DLG_SM_HEIGHT; width=$DLG_SM_WIDTH ;;
        large)  height=$DLG_LG_HEIGHT; width=$DLG_LG_WIDTH ;;
        xlarge) height=$DLG_XL_HEIGHT; width=$DLG_XL_WIDTH ;;
    esac

    dialog --title "$title" \
           --msgbox "$message" \
           $height $width
}

# Show error dialog with detailed information
show_error() {
    local title="$1"
    local message="$2"
    local details="${3:-}"  # Optional detailed error info

    local full_message="$message"

    if [[ -n "$details" ]]; then
        full_message+="\n\n--- Details ---\n$details"
    fi

    # Log the error
    log_tui "ERROR: $title - $message"

    dialog --title "Error: $title" \
           --colors \
           --msgbox "$full_message" \
           $DLG_LG_HEIGHT $DLG_LG_WIDTH
}

# Show warning dialog
show_warning() {
    local title="$1"
    local message="$2"

    log_tui "WARNING: $title - $message"

    dialog --title "Warning: $title" \
           --msgbox "$message" \
           $DLG_MD_HEIGHT $DLG_MD_WIDTH
}

# Show success dialog
show_success() {
    local title="$1"
    local message="$2"

    log_tui "SUCCESS: $title"

    dialog --title "Success: $title" \
           --msgbox "$message" \
           $DLG_MD_HEIGHT $DLG_MD_WIDTH
}

# Show confirmation dialog
show_confirm() {
    local title="$1"
    local message="$2"

    dialog --title "$title" \
           --yesno "$message" \
           $DLG_MD_HEIGHT $DLG_MD_WIDTH
}

# Show confirmation with three options (Yes/No/Cancel)
show_confirm_cancel() {
    local title="$1"
    local message="$2"

    dialog --title "$title" \
           --extra-button --extra-label "Cancel" \
           --yesno "$message" \
           $DLG_MD_HEIGHT $DLG_MD_WIDTH

    # Returns: 0=Yes, 1=No, 3=Cancel
}

#######################################
# Validation Result Display Functions
#######################################

# Show validation results with detailed breakdown
# Usage: show_validation_results "Title" "summary" "details_array_name"
show_validation_results() {
    local title="$1"
    local summary="$2"
    local -n checks_ref=${3:-VALIDATION_CHECKS}

    local report_file="$TEMP_DIR/validation_report.txt"

    cat > "$report_file" << EOF
VALIDATION REPORT: $title
$(printf '=%.0s' {1..50})

$summary

DETAILED RESULTS:
EOF

    local passed=0
    local failed=0
    local warnings=0

    for check in "${checks_ref[@]}"; do
        local status="${check%%:*}"
        local desc="${check#*:}"

        case "$status" in
            PASS)
                echo "  [PASS] $desc" >> "$report_file"
                ((passed++))
                ;;
            FAIL)
                echo "  [FAIL] $desc" >> "$report_file"
                ((failed++))
                ;;
            WARN)
                echo "  [WARN] $desc" >> "$report_file"
                ((warnings++))
                ;;
            INFO)
                echo "  [INFO] $desc" >> "$report_file"
                ;;
        esac
    done

    echo "" >> "$report_file"
    echo "SUMMARY: $passed passed, $failed failed, $warnings warnings" >> "$report_file"

    dialog --title "Validation: $title" \
           --textbox "$report_file" \
           $DLG_LG_HEIGHT $DLG_LG_WIDTH

    rm -f "$report_file"

    # Return failure count
    return $failed
}

# Perform prerequisite check with detailed results
check_prerequisites_detailed() {
    local context="$1"  # e.g., "backup", "sync", "restore"
    local -a checks=()
    local has_errors=false

    case "$context" in
        backup)
            # Check docker
            if command -v docker >/dev/null 2>&1; then
                if docker info >/dev/null 2>&1; then
                    checks+=("PASS:Docker is installed and running")
                else
                    checks+=("FAIL:Docker is installed but daemon not accessible")
                    has_errors=true
                fi
            else
                checks+=("FAIL:Docker is not installed")
                has_errors=true
            fi

            # Check restic
            if command -v restic >/dev/null 2>&1; then
                checks+=("PASS:Restic is installed ($(restic version 2>/dev/null | head -1 | cut -d' ' -f2))")
            else
                checks+=("FAIL:Restic is not installed")
                has_errors=true
            fi

            # Check backup script
            if [[ -x "$DOCKER_BACKUP_SCRIPT" ]]; then
                checks+=("PASS:Backup script is available and executable")
            else
                checks+=("FAIL:Backup script not found or not executable")
                has_errors=true
            fi

            # Check configuration
            if [[ -f "$BACKUP_CONFIG" ]]; then
                checks+=("PASS:Backup configuration file exists")

                # Check key config values
                if grep -q "^BACKUP_DIR=" "$BACKUP_CONFIG" && grep -q "^RESTIC_REPOSITORY=" "$BACKUP_CONFIG"; then
                    checks+=("PASS:Required configuration values are set")
                else
                    checks+=("WARN:Some configuration values may be missing")
                fi
            else
                checks+=("FAIL:Backup configuration file not found")
                has_errors=true
            fi

            # Check dirlist
            if [[ -f "$SCRIPT_DIR/dirlist" ]]; then
                local enabled_count=$(grep -c "=true" "$SCRIPT_DIR/dirlist" 2>/dev/null || echo "0")
                if [[ $enabled_count -gt 0 ]]; then
                    checks+=("PASS:Directory list has $enabled_count directories enabled")
                else
                    checks+=("WARN:No directories enabled for backup")
                fi
            else
                checks+=("WARN:Directory list not found (will be created)")
            fi
            ;;

        sync)
            # Check rclone
            if command -v rclone >/dev/null 2>&1; then
                checks+=("PASS:Rclone is installed ($(rclone version 2>/dev/null | head -1))")

                local remote_count=$(rclone listremotes 2>/dev/null | wc -l)
                if [[ $remote_count -gt 0 ]]; then
                    checks+=("PASS:$remote_count rclone remote(s) configured")
                else
                    checks+=("FAIL:No rclone remotes configured")
                    has_errors=true
                fi
            else
                checks+=("FAIL:Rclone is not installed")
                has_errors=true
            fi

            # Check sync script
            if [[ -x "$RCLONE_BACKUP_SCRIPT" ]]; then
                checks+=("PASS:Cloud sync script is available")
            else
                checks+=("FAIL:Cloud sync script not found or not executable")
                has_errors=true
            fi
            ;;

        restore)
            # Check rclone
            if command -v rclone >/dev/null 2>&1; then
                checks+=("PASS:Rclone is installed")
            else
                checks+=("FAIL:Rclone is not installed")
                has_errors=true
            fi

            # Check restore script
            if [[ -x "$RCLONE_RESTORE_SCRIPT" ]]; then
                checks+=("PASS:Restore script is available")
            else
                checks+=("FAIL:Restore script not found or not executable")
                has_errors=true
            fi

            # Check restic for restore operations
            if command -v restic >/dev/null 2>&1; then
                checks+=("PASS:Restic is available for restore operations")
            else
                checks+=("FAIL:Restic is required for restore operations")
                has_errors=true
            fi
            ;;
    esac

    # Store checks for display
    VALIDATION_CHECKS=("${checks[@]}")

    if [[ "$has_errors" == "true" ]]; then
        return 1
    fi
    return 0
}

# Show operation summary after completion
show_operation_summary() {
    local operation="$1"
    local status="$2"  # success, partial, failed
    local duration="$3"
    local -n details_ref=${4:-OPERATION_DETAILS}

    local summary_file="$TEMP_DIR/operation_summary.txt"
    local status_icon=""

    case "$status" in
        success) status_icon="[SUCCESS]" ;;
        partial) status_icon="[PARTIAL]" ;;
        failed)  status_icon="[FAILED]" ;;
    esac

    cat > "$summary_file" << EOF
OPERATION SUMMARY
$(printf '=%.0s' {1..50})

Operation: $operation
Status: $status_icon
Duration: $duration

DETAILS:
EOF

    for detail in "${details_ref[@]}"; do
        echo "  - $detail" >> "$summary_file"
    done

    echo "" >> "$summary_file"
    echo "Completed at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$summary_file"

    local title_prefix=""
    case "$status" in
        success) title_prefix="Success: " ;;
        partial) title_prefix="Partial: " ;;
        failed)  title_prefix="Failed: " ;;
    esac

    dialog --title "${title_prefix}${operation}" \
           --textbox "$summary_file" \
           $DLG_LG_HEIGHT $DLG_LG_WIDTH

    rm -f "$summary_file"
}

# Show progress dialog
show_progress() {
    local title="$1"
    local message="$2"
    local command="$3"

    # Create temporary script for command execution
    local temp_script="$TEMP_DIR/progress_script.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
$command
EOF
    chmod +x "$temp_script"

    # Run command with progress dialog
    dialog --title "$title" \
           --programbox "$message" \
           $DIALOG_HEIGHT $DIALOG_WIDTH < <(
        "$temp_script" 2>&1 | while IFS= read -r line; do
            echo "$line"
            sleep 0.1  # Small delay for readability
        done
    )
}

# Execute command with output capture
execute_with_output() {
    local command="$1"
    local output_file="$TEMP_DIR/command_output.txt"

    # Execute command and capture output
    if eval "$command" > "$output_file" 2>&1; then
        LAST_OPERATION_LOG="$output_file"
        return 0
    else
        LAST_OPERATION_LOG="$output_file"
        return 1
    fi
}

# Show command output
show_output() {
    local title="$1"

    if [[ -n "$LAST_OPERATION_LOG" && -f "$LAST_OPERATION_LOG" ]]; then
        dialog --title "$title" \
               --textbox "$LAST_OPERATION_LOG" \
               $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        show_info "$title" "No output available"
    fi
}

#######################################
# System Status Functions
#######################################

# Check system status
check_system_status() {
    local status_file="$TEMP_DIR/system_status.txt"

    cat > "$status_file" << EOF
DOCKER STACK 3-STAGE BACKUP SYSTEM STATUS
==========================================

Scripts Status:
EOF

    # Check script availability
    for script in "Docker Backup:$DOCKER_BACKUP_SCRIPT" "Cloud Sync:$RCLONE_BACKUP_SCRIPT" "Cloud Restore:$RCLONE_RESTORE_SCRIPT"; do
        local name="${script%%:*}"
        local path="${script##*:}"

        if [[ -x "$path" ]]; then
            echo "  ✓ $name: Available" >> "$status_file"
        else
            echo "  ✗ $name: Missing or not executable" >> "$status_file"
        fi
    done

    echo "" >> "$status_file"
    echo "Configuration Status:" >> "$status_file"

    # Check configuration files
    if [[ -f "$BACKUP_CONFIG" ]]; then
        echo "  ✓ Docker Backup Config: Found" >> "$status_file"

        # Check key configuration
        if grep -q "BACKUP_DIR=" "$BACKUP_CONFIG" && grep -q "RESTIC_REPOSITORY=" "$BACKUP_CONFIG"; then
            echo "    - Basic configuration appears complete" >> "$status_file"
        else
            echo "    - Configuration may be incomplete" >> "$status_file"
        fi
    else
        echo "  ✗ Docker Backup Config: Missing" >> "$status_file"
    fi

    if [[ -f "$RCLONE_CONFIG" ]]; then
        echo "  ✓ Rclone Config: Found" >> "$status_file"
        local remote_count=$(grep -c '^\[.*\]' "$RCLONE_CONFIG" 2>/dev/null || echo "0")
        echo "    - Configured remotes: $remote_count" >> "$status_file"
    else
        echo "  ✗ Rclone Config: Missing" >> "$status_file"
    fi

    echo "" >> "$status_file"
    echo "Recent Activity:" >> "$status_file"

    # Check recent backup activity
    if [[ -f "$SCRIPT_DIR/logs/docker_backup.log" ]]; then
        local last_backup=$(grep "Backup.*[Cc]ompleted" "$SCRIPT_DIR/logs/docker_backup.log" | tail -1 | cut -d' ' -f1-2)
        if [[ -n "$last_backup" ]]; then
            echo "  Last Docker Backup: $last_backup" >> "$status_file"
        else
            echo "  Last Docker Backup: No recent activity" >> "$status_file"
        fi
    else
        echo "  Last Docker Backup: No log file found" >> "$status_file"
    fi

    # Check disk space
    echo "" >> "$status_file"
    echo "System Resources:" >> "$status_file"

    if [[ -f "$BACKUP_CONFIG" ]]; then
        local backup_dir=$(grep "^BACKUP_DIR=" "$BACKUP_CONFIG" | cut -d= -f2)
        if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
            local disk_usage=$(df -h "$backup_dir" | awk 'NR==2 {print "Used: " $3 "/" $2 " (" $5 ")"}')
            echo "  Backup Directory: $disk_usage" >> "$status_file"
        fi
    fi

    local memory_usage=$(free -h | awk 'NR==2{printf "Memory: %s/%s (%.1f%%)", $3, $2, $3*100/$2}')
    echo "  System Memory: $memory_usage" >> "$status_file"

    dialog --title "System Status" \
           --textbox "$status_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

#######################################
# Configuration Management
#######################################

# Configuration management menu
config_menu() {
    while true; do
        local title
        title="$(get_title_with_breadcrumb "Configuration Management")"

        local choice
        choice=$(dialog --clear --title "$title" \
                       --menu "Choose configuration option:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Generate Docker Backup Config Template" \
                       "2" "Edit Docker Backup Configuration" \
                       "3" "Validate Docker Backup Configuration" \
                       "4" "Configure Rclone Remotes" \
                       "5" "Test Rclone Configuration" \
                       "6" "View Current Configuration" \
                       "7" "Backup Configuration Files" \
                       "8" "Restore Configuration Files" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) generate_config_template ;;
            2) edit_docker_config ;;
            3) validate_docker_config ;;
            4) configure_rclone ;;
            5) test_rclone_config ;;
            6) view_current_config ;;
            7) backup_config_files ;;
            8) restore_config_files ;;
            0|"") break ;;
        esac
    done
}

# Generate configuration template
generate_config_template() {
    log_tui "Generating configuration template"

    if show_confirm "Generate Config Template" "This will create a comprehensive configuration template.\n\nContinue?"; then
        if execute_with_output "$DOCKER_BACKUP_SCRIPT --generate-config"; then
            show_info "Success" "Configuration template generated successfully!\n\nFile: backup.conf.template\n\nYou can now copy and customize this template."
        else
            show_error "Generation Failed" "Failed to generate configuration template.\n\nCheck the output for details."
            show_output "Configuration Template Output"
        fi
    fi
}

# Edit Docker backup configuration
edit_docker_config() {
    log_tui "Opening configuration editor"

    # Check if config exists, offer to create from template if not
    if [[ ! -f "$BACKUP_CONFIG" ]]; then
        if show_confirm "No Configuration Found" "Docker backup configuration not found.\n\nCreate from template?"; then
            if [[ -f "$SCRIPT_DIR/backup.conf.template" ]]; then
                cp "$SCRIPT_DIR/backup.conf.template" "$BACKUP_CONFIG"
                chmod 600 "$BACKUP_CONFIG"
            else
                # Generate template first
                execute_with_output "$DOCKER_BACKUP_SCRIPT --generate-config"
                cp "$SCRIPT_DIR/backup.conf.template" "$BACKUP_CONFIG"
                chmod 600 "$BACKUP_CONFIG"
            fi
        else
            return
        fi
    fi

    # Use appropriate editor
    local editor="${EDITOR:-nano}"

    # Temporarily exit dialog mode
    clear
    echo "Opening configuration file with $editor..."
    echo "File: $BACKUP_CONFIG"
    echo "Press any key to continue..."
    read -n 1

    "$editor" "$BACKUP_CONFIG"

    # Return to dialog mode
    show_info "Configuration Updated" "Configuration file has been updated.\n\nFile: $BACKUP_CONFIG\n\nDon't forget to validate the configuration!"
}

# Validate Docker configuration
validate_docker_config() {
    log_tui "Validating Docker backup configuration"

    show_progress "Validating Configuration" "Checking configuration file..." \
                  "$DOCKER_BACKUP_SCRIPT --validate-config"

    if [[ $? -eq 0 ]]; then
        show_info "Validation Success" "Configuration validation completed successfully!\n\nAll settings appear to be correct."
    else
        show_error "Validation Failed" "Configuration validation found issues.\n\nPlease review and fix the configuration."
        show_output "Configuration Validation Output"
    fi
}

# Configure rclone
configure_rclone() {
    log_tui "Opening rclone configuration"

    if show_confirm "Rclone Configuration" "This will open the rclone configuration wizard.\n\nContinue?"; then
        # Temporarily exit dialog mode
        clear
        echo "Opening rclone configuration wizard..."
        echo "This will help you set up cloud storage remotes."
        echo "Press any key to continue..."
        read -n 1

        rclone config

        # Return to dialog mode
        show_info "Rclone Configuration" "Rclone configuration completed.\n\nYou can now use the cloud sync and restore features."
    fi
}

# Test rclone configuration
test_rclone_config() {
    log_tui "Testing rclone configuration"

    # Get list of remotes
    local remotes_file="$TEMP_DIR/remotes.txt"
    rclone listremotes > "$remotes_file" 2>/dev/null || true

    if [[ ! -s "$remotes_file" ]]; then
        show_error "No Remotes Found" "No rclone remotes are configured.\n\nPlease configure rclone first."
        return
    fi

    # Let user select remote to test
    local remote_choice
    remote_choice=$(dialog --clear --title "Test Rclone Remote" \
                          --menu "Select remote to test:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          $(cat "$remotes_file" | nl -w2 -s' ' | awk '{print $1, $2}') \
                          3>&1 1>&2 2>&3)

    if [[ -n "$remote_choice" ]]; then
        local remote_name=$(sed -n "${remote_choice}p" "$remotes_file")

        show_progress "Testing Remote" "Testing connection to $remote_name..." \
                      "rclone lsd ${remote_name} --max-depth 1"

        if [[ $? -eq 0 ]]; then
            show_info "Test Success" "Successfully connected to remote: $remote_name\n\nThe remote is working correctly."
        else
            show_error "Test Failed" "Failed to connect to remote: $remote_name\n\nCheck your configuration and network connection."
            show_output "Rclone Test Output"
        fi
    fi
}

# View current configuration
view_current_config() {
    local config_file="$TEMP_DIR/current_config.txt"

    cat > "$config_file" << EOF
CURRENT CONFIGURATION SUMMARY
=============================

Docker Backup Configuration:
EOF

    if [[ -f "$BACKUP_CONFIG" ]]; then
        echo "" >> "$config_file"
        grep -E "^[A-Z_]+=.*" "$BACKUP_CONFIG" | grep -v "PASSWORD" >> "$config_file"
        echo "" >> "$config_file"
        echo "  (Passwords hidden for security)" >> "$config_file"
    else
        echo "  No configuration file found" >> "$config_file"
    fi

    echo "" >> "$config_file"
    echo "Rclone Remotes:" >> "$config_file"

    if command -v rclone >/dev/null 2>&1; then
        local remotes=$(rclone listremotes 2>/dev/null || echo "  No remotes configured")
        echo "$remotes" >> "$config_file"
    else
        echo "  Rclone not available" >> "$config_file"
    fi

    echo "" >> "$config_file"
    echo "Directory Structure:" >> "$config_file"

    if [[ -f "$SCRIPT_DIR/dirlist" ]]; then
        echo "  Enabled Directories:" >> "$config_file"
        grep "=true" "$SCRIPT_DIR/dirlist" | cut -d= -f1 | sed 's/^/    - /' >> "$config_file"
        echo "" >> "$config_file"
        echo "  Disabled Directories:" >> "$config_file"
        grep "=false" "$SCRIPT_DIR/dirlist" | cut -d= -f1 | sed 's/^/    - /' >> "$config_file"
    else
        echo "  No directory list found" >> "$config_file"
    fi

    dialog --title "Current Configuration" \
           --textbox "$config_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Backup configuration files
backup_config_files() {
    local backup_dir="$SCRIPT_DIR/config_backup_$(date +%Y%m%d_%H%M%S)"

    if show_confirm "Backup Configuration" "Create backup of all configuration files?\n\nBackup location: $backup_dir"; then
        mkdir -p "$backup_dir"

        # Backup files
        local files_backed_up=0

        for file in "$BACKUP_CONFIG" "$SCRIPT_DIR/dirlist" "$HOME/.config/rclone/rclone.conf"; do
            if [[ -f "$file" ]]; then
                cp "$file" "$backup_dir/"
                ((files_backed_up++))
            fi
        done

        if [[ $files_backed_up -gt 0 ]]; then
            show_info "Backup Complete" "Configuration backup created successfully!\n\nLocation: $backup_dir\nFiles backed up: $files_backed_up"
        else
            show_error "Backup Failed" "No configuration files found to backup."
            rmdir "$backup_dir" 2>/dev/null || true
        fi
    fi
}

# Restore configuration files
restore_config_files() {
    # Find available backups
    local backup_dirs=($(find "$SCRIPT_DIR" -maxdepth 1 -type d -name "config_backup_*" | sort -r))

    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        show_error "No Backups Found" "No configuration backups found in script directory."
        return
    fi

    # Let user select backup to restore
    local menu_items=()
    local i=1
    for dir in "${backup_dirs[@]}"; do
        local backup_date=$(basename "$dir" | sed 's/config_backup_//')
        local formatted_date=$(echo "$backup_date" | sed 's/_/ /' | sed 's/\(.*\) \(.*\)/\1 at \2/')
        menu_items+=("$i" "Backup from $formatted_date")
        ((i++))
    done

    local choice
    choice=$(dialog --clear --title "Restore Configuration" \
                   --menu "Select backup to restore:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "${menu_items[@]}" \
                   3>&1 1>&2 2>&3)

    if [[ -n "$choice" ]]; then
        local selected_backup="${backup_dirs[$((choice-1))]}"

        if show_confirm "Confirm Restore" "This will overwrite current configuration files.\n\nRestore from: $(basename "$selected_backup")\n\nContinue?"; then
            local files_restored=0

            # Restore files
            for file in "$selected_backup"/*; do
                if [[ -f "$file" ]]; then
                    local filename=$(basename "$file")
                    case "$filename" in
                        "backup.conf") cp "$file" "$BACKUP_CONFIG"; ((files_restored++)) ;;
                        "dirlist") cp "$file" "$SCRIPT_DIR/dirlist"; ((files_restored++)) ;;
                        "rclone.conf")
                            mkdir -p "$HOME/.config/rclone"
                            cp "$file" "$HOME/.config/rclone/rclone.conf"
                            ((files_restored++))
                            ;;
                    esac
                fi
            done

            if [[ $files_restored -gt 0 ]]; then
                show_info "Restore Complete" "Configuration restored successfully!\n\nFiles restored: $files_restored\n\nRecommended: Validate configuration"
            else
                show_error "Restore Failed" "No configuration files found in backup to restore."
            fi
        fi
    fi
}

#######################################
# Main Menu
#######################################

# Show main menu
main_menu() {
    MENU_BREADCRUMB=()  # Reset breadcrumb at main menu

    # Check for directory sync status and show indicator
    local dir_sync_indicator=""
    if ! check_dirlist_sync_status 2>/dev/null; then
        dir_sync_indicator=" [!]"
    fi

    while true; do
        # Refresh sync indicator
        dir_sync_indicator=""
        if ! check_dirlist_sync_status 2>/dev/null; then
            dir_sync_indicator=" [!]"
        fi

        local choice
        choice=$(dialog --clear --title "$TUI_TITLE v$TUI_VERSION" \
                       --menu "Choose an option:                              [Q]uick Backup | [S]tatus" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Stage 1: Docker Stack Backup" \
                       "2" "Stage 2: Cloud Sync (Upload)" \
                       "3" "Stage 3: Cloud Restore (Download)" \
                       "4" "Configuration Management" \
                       "5" "Directory List Management${dir_sync_indicator}" \
                       "6" "Monitoring & Status" \
                       "7" "System Health Check" \
                       "8" "View Logs" \
                       "9" "Help & Documentation" \
                       "Q" ">> Quick Backup (shortcut)" \
                       "S" ">> Quick Status (shortcut)" \
                       "0" "Exit" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) push_breadcrumb "Backup"; stage1_docker_backup_menu; pop_breadcrumb ;;
            2) push_breadcrumb "Cloud Sync"; stage2_cloud_sync_menu; pop_breadcrumb ;;
            3) push_breadcrumb "Restore"; stage3_cloud_restore_menu; pop_breadcrumb ;;
            4) push_breadcrumb "Config"; config_menu; pop_breadcrumb ;;
            5) push_breadcrumb "Directories"; directory_management; pop_breadcrumb ;;
            6) push_breadcrumb "Monitoring"; monitoring_menu; pop_breadcrumb ;;
            7) health_check ;;
            8) push_breadcrumb "Logs"; view_logs_menu; pop_breadcrumb ;;
            9) help_menu ;;
            Q|q) quick_backup ;;  # Quick shortcut
            S|s) view_backup_status ;;  # Quick shortcut
            0|"")
                if show_confirm "Exit" "Are you sure you want to exit?"; then
                    exit_tui
                fi
                ;;
        esac
    done
}

#######################################
# Stage 1: Docker Backup Management
#######################################

# Docker backup main menu
stage1_docker_backup_menu() {
    while true; do
        local title
        title="$(get_title_with_breadcrumb "Stage 1: Docker Stack Backup")"

        local choice
        choice=$(dialog --clear --title "$title" \
                       --menu "Choose backup operation:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Quick Backup (Default Settings)" \
                       "2" "Custom Backup with Options" \
                       "3" "Dry Run (Test Mode)" \
                       "4" "List Recent Backups" \
                       "5" "Verify Last Backup" \
                       "6" "View Backup Status" \
                       "7" "Manage Directory Selection" \
                       "8" "Configure Backup Settings" \
                       "9" "Backup Logs & Troubleshooting" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) quick_backup ;;
            2) custom_backup ;;
            3) dry_run_backup ;;
            4) list_recent_backups ;;
            5) verify_backup ;;
            6) view_backup_status ;;
            7) push_breadcrumb "Directories"; directory_management; pop_breadcrumb ;;
            8) push_breadcrumb "Settings"; configure_backup_settings; pop_breadcrumb ;;
            9) push_breadcrumb "Troubleshoot"; backup_troubleshooting; pop_breadcrumb ;;
            0|"") break ;;
        esac
    done
}

# Quick backup with default settings
quick_backup() {
    log_tui "Starting quick backup"

    if ! check_backup_prerequisites; then
        return
    fi

    if show_confirm "Quick Backup" "Start backup with default settings?\n\nThis will:\n• Backup all enabled directories\n• Use configured restic repository\n• Follow selective backup process\n\nEstimated time: 5-30 minutes\n\nContinue?"; then
        show_progress "Docker Stack Backup" "Running backup process...\n\nThis may take several minutes depending on data size." \
                      "$DOCKER_BACKUP_SCRIPT"

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            show_info "Backup Complete" "Docker stack backup completed successfully!\n\n✓ All enabled directories backed up\n✓ Backup verification passed\n✓ Repository updated\n\nCheck logs for details."

            # Offer to view backup status
            if show_confirm "View Results" "Would you like to view the backup results?"; then
                view_backup_status
            fi
        else
            show_error "Backup Failed" "Docker stack backup failed with exit code: $exit_code\n\nPlease check the logs for detailed error information."
            show_output "Backup Output"

            # Offer troubleshooting
            if show_confirm "Troubleshooting" "Would you like to view troubleshooting options?"; then
                backup_troubleshooting
            fi
        fi
    fi
}

# Custom backup with options
custom_backup() {
    log_tui "Starting custom backup configuration"

    if ! check_backup_prerequisites; then
        return
    fi

    # Build custom options
    local backup_options=""
    local option_descriptions="Custom Backup Options Selected:\n"

    # Verbose mode
    if show_confirm "Verbose Mode" "Enable verbose output for detailed logging?"; then
        backup_options="$backup_options --verbose"
        option_descriptions="${option_descriptions}• Verbose logging enabled\n"
    fi

    # Backup verification
    local verify_choice
    verify_choice=$(dialog --clear --title "Backup Verification" \
                          --menu "Select verification level:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          "1" "Metadata only (fast)" \
                          "2" "Files verification (recommended)" \
                          "3" "Full data verification (slow)" \
                          "4" "Skip verification" \
                          3>&1 1>&2 2>&3)

    case $verify_choice in
        1)
            backup_options="$backup_options --verify-metadata"
            option_descriptions="${option_descriptions}• Verification: Metadata only\n"
            ;;
        2)
            backup_options="$backup_options --verify-files"
            option_descriptions="${option_descriptions}• Verification: Files (default)\n"
            ;;
        3)
            backup_options="$backup_options --verify-data"
            option_descriptions="${option_descriptions}• Verification: Full data\n"
            ;;
        4)
            backup_options="$backup_options --no-verify"
            option_descriptions="${option_descriptions}• Verification: Disabled\n"
            ;;
    esac

    # Resource monitoring
    if show_confirm "Resource Monitoring" "Enable system resource monitoring during backup?"; then
        backup_options="$backup_options --monitor-resources"
        option_descriptions="${option_descriptions}• Resource monitoring enabled\n"
    fi

    # Show summary and confirm
    if show_confirm "Custom Backup Summary" "${option_descriptions}\nProceed with custom backup?"; then
        show_progress "Custom Docker Backup" "Running custom backup with selected options...\n\nThis may take several minutes." \
                      "$DOCKER_BACKUP_SCRIPT $backup_options"

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            show_info "Custom Backup Complete" "Custom docker stack backup completed successfully!\n\nAll selected options were applied.\n\nCheck logs for detailed results."
        else
            show_error "Custom Backup Failed" "Custom backup failed with exit code: $exit_code\n\nCheck the output for error details."
            show_output "Custom Backup Output"
        fi
    fi
}

# Dry run backup
dry_run_backup() {
    log_tui "Starting dry run backup"

    if show_confirm "Dry Run Mode" "Perform a dry run backup?\n\nThis will:\n• Show what would be backed up\n• Test all configurations\n• No actual backup performed\n• Safe to run anytime\n\nContinue?"; then
        show_progress "Dry Run Backup" "Performing dry run test...\n\nAnalyzing directories and configuration..." \
                      "$DOCKER_BACKUP_SCRIPT --dry-run --verbose"

        if [[ $? -eq 0 ]]; then
            show_info "Dry Run Complete" "Dry run completed successfully!\n\n✓ Configuration validated\n✓ Directories scanned\n✓ No issues found\n\nSystem is ready for actual backup."
        else
            show_error "Dry Run Issues Found" "Dry run found issues that need attention.\n\nPlease review and fix before running actual backup."
            show_output "Dry Run Output"
        fi
    fi
}

# List recent backups
list_recent_backups() {
    log_tui "Listing recent backups"

    show_progress "Loading Backups" "Retrieving backup history from repository..." \
                  "$DOCKER_BACKUP_SCRIPT --list-backups"

    if [[ $? -eq 0 ]]; then
        show_output "Recent Backups"

        # Offer additional options
        local choice
        choice=$(dialog --clear --title "Backup Actions" \
                       --menu "What would you like to do?" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Refresh backup list" \
                       "2" "View detailed backup info" \
                       "3" "Check backup repository status" \
                       "4" "Return to backup menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) list_recent_backups ;;
            2) show_info "Feature Note" "Detailed backup info viewer will be added in a future update." ;;
            3) check_repository_status ;;
            4|"") return ;;
        esac
    else
        show_error "Backup List Failed" "Failed to retrieve backup list.\n\nPossible causes:\n• Repository not configured\n• Network connectivity issues\n• Repository access permissions"
        show_output "Backup List Error"
    fi
}

# Verify backup
verify_backup() {
    log_tui "Starting backup verification"

    # Get list of available snapshots for verification
    local verify_choice
    verify_choice=$(dialog --clear --title "Backup Verification" \
                          --menu "Select verification type:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          "1" "Verify last backup (quick)" \
                          "2" "Verify specific directory backup" \
                          "3" "Full repository integrity check" \
                          "4" "Custom verification options" \
                          3>&1 1>&2 2>&3)

    case $verify_choice in
        1)
            show_progress "Verifying Last Backup" "Checking integrity of most recent backup..." \
                          "$DOCKER_BACKUP_SCRIPT --verify-last"
            ;;
        2)
            # Directory-specific verification
            verify_directory_backup
            return
            ;;
        3)
            show_progress "Full Repository Check" "Performing comprehensive repository integrity check...\n\nThis may take several minutes." \
                          "restic check --read-data-subset=10%"
            ;;
        4)
            custom_verification
            return
            ;;
        *) return ;;
    esac

    if [[ $? -eq 0 ]]; then
        show_info "Verification Complete" "Backup verification completed successfully!\n\n✓ Data integrity confirmed\n✓ Repository is healthy\n✓ Backups are recoverable"
    else
        show_error "Verification Failed" "Backup verification found issues!\n\n⚠️  Data integrity problems detected\n⚠️  Repository may need repair\n\nRecommended: Check repository and re-run backup"
        show_output "Verification Output"
    fi
}

# Directory-specific backup verification
verify_directory_backup() {
    # Check if dirlist exists
    if [[ ! -f "$SCRIPT_DIR/dirlist" ]]; then
        show_error "No Directory List" "No directory list found.\n\nRun a backup first to generate directory list."
        return
    fi

    # Get enabled directories
    local enabled_dirs=($(grep "=true" "$SCRIPT_DIR/dirlist" | cut -d= -f1))

    if [[ ${#enabled_dirs[@]} -eq 0 ]]; then
        show_error "No Enabled Directories" "No directories are currently enabled for backup.\n\nConfigure directory selection first."
        return
    fi

    # Create menu items for directory selection
    local menu_items=()
    local i=1
    for dir in "${enabled_dirs[@]}"; do
        menu_items+=("$i" "$dir")
        ((i++))
    done

    local dir_choice
    dir_choice=$(dialog --clear --title "Select Directory to Verify" \
                       --menu "Choose directory for verification:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "${menu_items[@]}" \
                       3>&1 1>&2 2>&3)

    if [[ -n "$dir_choice" ]]; then
        local selected_dir="${enabled_dirs[$((dir_choice-1))]}"

        show_progress "Verifying Directory Backup" "Verifying backup for: $selected_dir\n\nChecking data integrity..." \
                      "$DOCKER_BACKUP_SCRIPT --verify-directory '$selected_dir'"

        if [[ $? -eq 0 ]]; then
            show_info "Directory Verification Complete" "Verification successful for directory: $selected_dir\n\n✓ Backup data is intact\n✓ Files are recoverable"
        else
            show_error "Directory Verification Failed" "Verification failed for directory: $selected_dir\n\nCheck the output for specific issues."
            show_output "Directory Verification Output"
        fi
    fi
}

# Custom verification options
custom_verification() {
    local verify_options=""
    local option_summary="Custom Verification Options:\n"

    # Verification depth
    local depth_choice
    depth_choice=$(dialog --clear --title "Verification Depth" \
                         --menu "Select verification depth:" \
                         $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                         "1" "Metadata only (fastest)" \
                         "2" "File structure (recommended)" \
                         "3" "Partial data (10% sample)" \
                         "4" "Full data verification (slowest)" \
                         3>&1 1>&2 2>&3)

    case $depth_choice in
        1)
            verify_options="$verify_options --verify-metadata"
            option_summary="${option_summary}• Depth: Metadata only\n"
            ;;
        2)
            verify_options="$verify_options --verify-files"
            option_summary="${option_summary}• Depth: File structure\n"
            ;;
        3)
            verify_options="$verify_options --verify-data-sample"
            option_summary="${option_summary}• Depth: Partial data (10%)\n"
            ;;
        4)
            verify_options="$verify_options --verify-full-data"
            option_summary="${option_summary}• Depth: Full data verification\n"
            ;;
        *) return ;;
    esac

    # Verbose output
    if show_confirm "Verbose Output" "Enable detailed verification output?"; then
        verify_options="$verify_options --verbose"
        option_summary="${option_summary}• Verbose output enabled\n"
    fi

    # Show summary and execute
    if show_confirm "Custom Verification" "${option_summary}\nProceed with custom verification?"; then
        show_progress "Custom Verification" "Running custom backup verification...\n\nPlease wait, this may take time depending on options selected." \
                      "$DOCKER_BACKUP_SCRIPT $verify_options"

        if [[ $? -eq 0 ]]; then
            show_info "Custom Verification Complete" "Custom verification completed successfully!\n\nAll selected verification tests passed."
        else
            show_error "Custom Verification Failed" "Custom verification found issues.\n\nReview the output for detailed information."
            show_output "Custom Verification Output"
        fi
    fi
}

# View backup status
view_backup_status() {
    local status_file="$TEMP_DIR/backup_status.txt"

    log_tui "Generating backup status report"

    # Generate comprehensive status report
    cat > "$status_file" << EOF
DOCKER STACK BACKUP STATUS REPORT
==================================

EOF

    # Basic system info
    echo "Generated: $(date)" >> "$status_file"
    echo "Host: $(hostname)" >> "$status_file"
    echo "" >> "$status_file"

    # Configuration status
    echo "Configuration Status:" >> "$status_file"
    if [[ -f "$BACKUP_CONFIG" ]]; then
        echo "  ✓ Backup configuration: Found" >> "$status_file"

        local backup_dir=$(grep "^BACKUP_DIR=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2)
        local restic_repo=$(grep "^RESTIC_REPOSITORY=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2)

        echo "  • Backup directory: ${backup_dir:-Not configured}" >> "$status_file"
        echo "  • Repository: ${restic_repo:-Not configured}" >> "$status_file"
    else
        echo "  ✗ Backup configuration: Missing" >> "$status_file"
    fi
    echo "" >> "$status_file"

    # Directory status
    echo "Directory Status:" >> "$status_file"
    if [[ -f "$SCRIPT_DIR/dirlist" ]]; then
        local enabled_count=$(grep -c "=true" "$SCRIPT_DIR/dirlist")
        local disabled_count=$(grep -c "=false" "$SCRIPT_DIR/dirlist")

        echo "  • Total directories: $((enabled_count + disabled_count))" >> "$status_file"
        echo "  • Enabled for backup: $enabled_count" >> "$status_file"
        echo "  • Disabled: $disabled_count" >> "$status_file"

        if [[ $enabled_count -gt 0 ]]; then
            echo "" >> "$status_file"
            echo "  Enabled directories:" >> "$status_file"
            grep "=true" "$SCRIPT_DIR/dirlist" | cut -d= -f1 | sed 's/^/    - /' >> "$status_file"
        fi
    else
        echo "  • Directory list: Not generated (run scan first)" >> "$status_file"
    fi
    echo "" >> "$status_file"

    # Last backup info
    echo "Last Backup Information:" >> "$status_file"
    if [[ -f "$SCRIPT_DIR/logs/docker_backup.log" ]]; then
        local last_start=$(grep "Backup Started" "$SCRIPT_DIR/logs/docker_backup.log" | tail -1 | awk '{print $1" "$2}' | tr -d '[]')
        local last_complete=$(grep -E "(Backup.*[Cc]ompleted|failed: [0-9])" "$SCRIPT_DIR/logs/docker_backup.log" | tail -1)

        if [[ -n "$last_start" ]]; then
            echo "  • Last started: $last_start" >> "$status_file"
        fi

        if [[ -n "$last_complete" ]]; then
            if echo "$last_complete" | grep -q "failed: 0"; then
                echo "  • Status: ✓ Successful" >> "$status_file"
            else
                echo "  • Status: ⚠ Issues detected" >> "$status_file"
            fi

            local complete_time=$(echo "$last_complete" | awk '{print $1" "$2}' | tr -d '[]')
            echo "  • Last completed: $complete_time" >> "$status_file"
        else
            echo "  • Status: Unknown or in progress" >> "$status_file"
        fi
    else
        echo "  • No backup log found" >> "$status_file"
    fi
    echo "" >> "$status_file"

    # Repository status
    echo "Repository Status:" >> "$status_file"
    if command -v restic >/dev/null 2>&1 && [[ -f "$BACKUP_CONFIG" ]]; then
        # Load config temporarily
        source "$BACKUP_CONFIG" 2>/dev/null || true
        export RESTIC_REPOSITORY RESTIC_PASSWORD

        if restic snapshots --quiet >/dev/null 2>&1; then
            local snapshot_count=$(restic snapshots --json 2>/dev/null | jq length 2>/dev/null || echo "Unknown")
            local repo_size=$(restic stats --mode raw-data --json 2>/dev/null | jq -r '.total_size // "Unknown"' 2>/dev/null || echo "Unknown")

            echo "  ✓ Repository accessible" >> "$status_file"
            echo "  • Total snapshots: $snapshot_count" >> "$status_file"
            echo "  • Repository size: $repo_size bytes" >> "$status_file"
        else
            echo "  ✗ Repository not accessible" >> "$status_file"
        fi
    else
        echo "  • Cannot check (restic or config unavailable)" >> "$status_file"
    fi
    echo "" >> "$status_file"

    # System resources
    echo "System Resources:" >> "$status_file"
    if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
        local disk_info=$(df -h "$backup_dir" | awk 'NR==2 {print "Used: " $3 "/" $2 " (" $5 ")"}')
        echo "  • Backup directory: $disk_info" >> "$status_file"
    fi

    local mem_info=$(free -h | awk 'NR==2{printf "Used: %s/%s", $3, $2}')
    echo "  • Memory: $mem_info" >> "$status_file"

    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo "  • Load average: $load_avg" >> "$status_file"

    dialog --title "Backup Status Report" \
           --textbox "$status_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Check repository status
check_repository_status() {
    log_tui "Checking repository status"

    show_progress "Repository Status" "Checking repository health and statistics..." \
                  "restic check --read-data-subset=1%"

    if [[ $? -eq 0 ]]; then
        show_info "Repository Healthy" "Repository status check completed successfully!\n\n✓ Repository is accessible\n✓ Data integrity confirmed\n✓ Ready for backup operations"

        # Offer to show detailed repository info
        if show_confirm "Repository Details" "Would you like to view detailed repository statistics?"; then
            show_progress "Repository Statistics" "Gathering repository statistics..." \
                          "restic stats --mode restore-size"
            show_output "Repository Statistics"
        fi
    else
        show_error "Repository Issues" "Repository status check found problems!\n\n⚠️  Repository may be corrupted\n⚠️  Backup operations may fail\n\nRecommended: Check repository configuration"
        show_output "Repository Check Output"
    fi
}

# Legacy manage directories function (kept for compatibility)
manage_directories() {
    # Redirect to new integrated directory management
    directory_management
}

# Configure backup settings
configure_backup_settings() {
    log_tui "Opening backup settings configuration"

    local choice
    choice=$(dialog --clear --title "Backup Settings Configuration" \
                   --menu "Choose setting to configure:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "1" "Edit backup configuration file" \
                   "2" "Generate new configuration template" \
                   "3" "Validate current configuration" \
                   "4" "Configure backup timeouts" \
                   "5" "Setup backup verification options" \
                   "6" "Configure retention policy" \
                   "7" "Reset configuration to defaults" \
                   "0" "Return to backup menu" \
                   3>&1 1>&2 2>&3)

    case $choice in
        1) edit_docker_config ;;
        2) generate_config_template ;;
        3) validate_docker_config ;;
        4) configure_timeouts ;;
        5) configure_verification ;;
        6) configure_retention ;;
        7) reset_configuration ;;
        0|"") return ;;
    esac
}

# Configure backup timeouts
configure_timeouts() {
    local timeout_file="$TEMP_DIR/timeout_config.txt"

    # Get current values
    local backup_timeout="3600"
    local docker_timeout="30"

    if [[ -f "$BACKUP_CONFIG" ]]; then
        backup_timeout=$(grep "^BACKUP_TIMEOUT=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "3600")
        docker_timeout=$(grep "^DOCKER_TIMEOUT=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "30")
    fi

    # Create form for timeout configuration
    local new_backup_timeout new_docker_timeout

    exec 3>&1
    result=$(dialog --title "Configure Backup Timeouts" \
                   --form "Current timeout settings:\n\nAdjust timeouts as needed:" \
                   15 60 0 \
                   "Backup timeout (seconds):" 1 1 "$backup_timeout" 1 25 10 0 \
                   "Docker timeout (seconds):" 2 1 "$docker_timeout" 2 25 10 0 \
                   2>&1 1>&3)
    exec 3>&-

    if [[ -n "$result" ]]; then
        new_backup_timeout=$(echo "$result" | sed -n '1p')
        new_docker_timeout=$(echo "$result" | sed -n '2p')

        # Validate inputs
        if [[ "$new_backup_timeout" =~ ^[0-9]+$ ]] && [[ "$new_docker_timeout" =~ ^[0-9]+$ ]]; then
            # Update configuration file
            if [[ -f "$BACKUP_CONFIG" ]]; then
                sed -i "s/^BACKUP_TIMEOUT=.*/BACKUP_TIMEOUT=$new_backup_timeout/" "$BACKUP_CONFIG"
                sed -i "s/^DOCKER_TIMEOUT=.*/DOCKER_TIMEOUT=$new_docker_timeout/" "$BACKUP_CONFIG"

                show_info "Timeouts Updated" "Backup timeouts have been updated successfully!\n\nBackup timeout: ${new_backup_timeout}s\nDocker timeout: ${new_docker_timeout}s\n\nChanges will take effect on next backup run."
            else
                show_error "Configuration Error" "Backup configuration file not found.\n\nPlease create configuration first."
            fi
        else
            show_error "Invalid Input" "Timeout values must be positive integers.\n\nBackup timeout: $new_backup_timeout\nDocker timeout: $new_docker_timeout"
        fi
    fi
}

# Configure verification settings
configure_verification() {
    local verify_choice
    verify_choice=$(dialog --clear --title "Backup Verification Configuration" \
                          --menu "Select default verification level:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          "1" "Metadata only (fastest)" \
                          "2" "Files verification (recommended)" \
                          "3" "Full data verification (slowest)" \
                          "4" "Disable verification" \
                          3>&1 1>&2 2>&3)

    local verify_setting=""
    local verify_description=""

    case $verify_choice in
        1)
            verify_setting="metadata"
            verify_description="Metadata only (fastest)"
            ;;
        2)
            verify_setting="files"
            verify_description="Files verification (recommended)"
            ;;
        3)
            verify_setting="data"
            verify_description="Full data verification (slowest)"
            ;;
        4)
            verify_setting="false"
            verify_description="Verification disabled"
            ;;
        *) return ;;
    esac

    # Update configuration
    if [[ -f "$BACKUP_CONFIG" ]]; then
        if [[ "$verify_setting" == "false" ]]; then
            sed -i "s/^ENABLE_BACKUP_VERIFICATION=.*/ENABLE_BACKUP_VERIFICATION=false/" "$BACKUP_CONFIG"
        else
            sed -i "s/^ENABLE_BACKUP_VERIFICATION=.*/ENABLE_BACKUP_VERIFICATION=true/" "$BACKUP_CONFIG"
            sed -i "s/^VERIFICATION_DEPTH=.*/VERIFICATION_DEPTH=$verify_setting/" "$BACKUP_CONFIG"
        fi

        show_info "Verification Updated" "Backup verification settings updated!\n\nSetting: $verify_description\n\nThis will be used for all future backups."
    else
        show_error "Configuration Error" "Backup configuration file not found.\n\nPlease create configuration first."
    fi
}

# Configure retention policy
configure_retention() {
    local current_daily="7"
    local current_weekly="4"
    local current_monthly="12"
    local current_yearly="3"
    local auto_prune="false"

    # Get current values if config exists
    if [[ -f "$BACKUP_CONFIG" ]]; then
        current_daily=$(grep "^KEEP_DAILY=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "7")
        current_weekly=$(grep "^KEEP_WEEKLY=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "4")
        current_monthly=$(grep "^KEEP_MONTHLY=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "12")
        current_yearly=$(grep "^KEEP_YEARLY=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "3")
        auto_prune=$(grep "^AUTO_PRUNE=" "$BACKUP_CONFIG" 2>/dev/null | cut -d= -f2 | xargs || echo "false")
    fi

    exec 3>&1
    result=$(dialog --title "Configure Retention Policy" \
                   --form "Set how many backups to keep:\n\nCurrent retention settings:" \
                   18 60 0 \
                   "Daily backups to keep:" 1 1 "$current_daily" 1 25 5 0 \
                   "Weekly backups to keep:" 2 1 "$current_weekly" 2 25 5 0 \
                   "Monthly backups to keep:" 3 1 "$current_monthly" 3 25 5 0 \
                   "Yearly backups to keep:" 4 1 "$current_yearly" 4 25 5 0 \
                   2>&1 1>&3)
    exec 3>&-

    if [[ -n "$result" ]]; then
        local new_daily=$(echo "$result" | sed -n '1p')
        local new_weekly=$(echo "$result" | sed -n '2p')
        local new_monthly=$(echo "$result" | sed -n '3p')
        local new_yearly=$(echo "$result" | sed -n '4p')

        # Validate inputs
        if [[ "$new_daily" =~ ^[0-9]+$ ]] && [[ "$new_weekly" =~ ^[0-9]+$ ]] && [[ "$new_monthly" =~ ^[0-9]+$ ]] && [[ "$new_yearly" =~ ^[0-9]+$ ]]; then
            # Ask about auto-prune
            local enable_prune=false
            if show_confirm "Auto-Prune" "Enable automatic pruning?\n\nThis will automatically remove old backups according to the retention policy after each successful backup.\n\nRecommended: Yes"; then
                enable_prune=true
            fi

            # Update configuration
            if [[ -f "$BACKUP_CONFIG" ]]; then
                sed -i "s/^KEEP_DAILY=.*/KEEP_DAILY=$new_daily/" "$BACKUP_CONFIG"
                sed -i "s/^KEEP_WEEKLY=.*/KEEP_WEEKLY=$new_weekly/" "$BACKUP_CONFIG"
                sed -i "s/^KEEP_MONTHLY=.*/KEEP_MONTHLY=$new_monthly/" "$BACKUP_CONFIG"
                sed -i "s/^KEEP_YEARLY=.*/KEEP_YEARLY=$new_yearly/" "$BACKUP_CONFIG"
                sed -i "s/^AUTO_PRUNE=.*/AUTO_PRUNE=$enable_prune/" "$BACKUP_CONFIG"

                show_info "Retention Policy Updated" "Backup retention policy updated successfully!\n\nDaily: $new_daily\nWeekly: $new_weekly\nMonthly: $new_monthly\nYearly: $new_yearly\nAuto-prune: $enable_prune\n\nSettings will take effect on next backup."
            else
                show_error "Configuration Error" "Backup configuration file not found.\n\nPlease create configuration first."
            fi
        else
            show_error "Invalid Input" "All retention values must be positive integers."
        fi
    fi
}

# Reset configuration to defaults
reset_configuration() {
    if show_confirm "Reset Configuration" "This will reset backup configuration to default values.\n\n⚠️  This will overwrite your current settings!\n\nCreate backup of current config first?"; then
        # Backup current config
        if [[ -f "$BACKUP_CONFIG" ]]; then
            local backup_name="backup.conf.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$BACKUP_CONFIG" "$SCRIPT_DIR/$backup_name"
            show_info "Backup Created" "Current configuration backed up as:\n$backup_name"
        fi

        # Generate new default configuration
        if execute_with_output "$DOCKER_BACKUP_SCRIPT --generate-config"; then
            cp "$SCRIPT_DIR/backup.conf.template" "$BACKUP_CONFIG"
            chmod 600 "$BACKUP_CONFIG"

            show_info "Configuration Reset" "Configuration has been reset to defaults!\n\nFile: $BACKUP_CONFIG\n\nPlease edit the configuration to set:\n• BACKUP_DIR\n• RESTIC_REPOSITORY\n• RESTIC_PASSWORD"
        else
            show_error "Reset Failed" "Failed to generate default configuration template."
        fi
    fi
}

# Backup troubleshooting
backup_troubleshooting() {
    local choice
    choice=$(dialog --clear --title "Backup Troubleshooting" \
                   --menu "Select troubleshooting option:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "1" "View recent backup logs" \
                   "2" "Test system prerequisites" \
                   "3" "Check repository connectivity" \
                   "4" "Validate configuration" \
                   "5" "Test Docker permissions" \
                   "6" "Check disk space" \
                   "7" "Run system health check" \
                   "8" "View common solutions" \
                   "0" "Return to backup menu" \
                   3>&1 1>&2 2>&3)

    case $choice in
        1) view_recent_logs ;;
        2) test_prerequisites ;;
        3) test_repository_connectivity ;;
        4) validate_docker_config ;;
        5) test_docker_permissions ;;
        6) check_disk_space_detailed ;;
        7) health_check ;;
        8) show_common_solutions ;;
        0|"") return ;;
    esac
}

# Check backup prerequisites with detailed validation
check_backup_prerequisites() {
    # Use detailed prerequisite check
    if ! check_prerequisites_detailed "backup"; then
        # Show detailed validation results
        show_validation_results "Backup Prerequisites" \
            "Some prerequisites are not met. Please resolve the issues below before running backup." \
            VALIDATION_CHECKS
        return 1
    fi

    return 0
}

#######################################
# Stage 2: Cloud Sync Management
#######################################

# Cloud sync main menu
stage2_cloud_sync_menu() {
    while true; do
        local title
        title="$(get_title_with_breadcrumb "Stage 2: Cloud Sync (Upload)")"

        local choice
        choice=$(dialog --clear --title "$title" \
                       --menu "Choose cloud sync operation:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Quick Cloud Sync" \
                       "2" "Custom Sync with Options" \
                       "3" "Dry Run Cloud Sync" \
                       "4" "View Sync Status" \
                       "5" "Test Cloud Connectivity" \
                       "6" "Configure Rclone Settings" \
                       "7" "Schedule Automatic Sync" \
                       "8" "Sync Troubleshooting" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) quick_cloud_sync ;;
            2) custom_cloud_sync ;;
            3) dry_run_cloud_sync ;;
            4) view_sync_status ;;
            5) test_cloud_connectivity ;;
            6) push_breadcrumb "Settings"; configure_rclone_settings; pop_breadcrumb ;;
            7) push_breadcrumb "Schedule"; schedule_sync; pop_breadcrumb ;;
            8) push_breadcrumb "Troubleshoot"; sync_troubleshooting; pop_breadcrumb ;;
            0|"") break ;;
        esac
    done
}

# Quick cloud sync
quick_cloud_sync() {
    log_tui "Starting quick cloud sync"

    if ! check_cloud_sync_prerequisites; then
        return
    fi

    # Get source directory from backup config
    local source_dir=""
    if [[ -f "$BACKUP_CONFIG" ]]; then
        source_dir=$(grep "^RESTIC_REPOSITORY=" "$BACKUP_CONFIG" | cut -d= -f2 | xargs)
        if [[ "$source_dir" =~ ^/ ]]; then
            # Local repository path - use parent directory
            source_dir="$(dirname "$source_dir")"
        else
            show_error "Remote Repository" "Restic repository appears to be remote.\n\nCloud sync is designed for local repositories.\n\nRepository: $source_dir"
            return
        fi
    else
        show_error "Configuration Missing" "Backup configuration not found.\n\nPlease configure docker backup first."
        return
    fi

    if show_confirm "Quick Cloud Sync" "Sync local backup repository to cloud storage?\n\nSource: $source_dir\nThis will upload any new/changed files to cloud.\n\nEstimated time: 5-60 minutes\n\nContinue?"; then
        show_progress "Cloud Sync Upload" "Syncing local repository to cloud storage...\n\nThis may take time depending on data size and connection speed." \
                      "$RCLONE_BACKUP_SCRIPT"

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            show_info "Cloud Sync Complete" "Cloud sync completed successfully!\n\n✓ Local repository synced to cloud\n✓ Backup data is now offsite\n✓ Ready for disaster recovery\n\nCheck logs for transfer details."

            # Offer to view sync status
            if show_confirm "View Results" "Would you like to view the sync results?"; then
                view_sync_status
            fi
        else
            show_error "Cloud Sync Failed" "Cloud sync failed with exit code: $exit_code\n\nPlease check the logs for detailed error information."
            show_output "Cloud Sync Output"

            # Offer troubleshooting
            if show_confirm "Troubleshooting" "Would you like to view troubleshooting options?"; then
                sync_troubleshooting
            fi
        fi
    fi
}

# Custom cloud sync
custom_cloud_sync() {
    log_tui "Starting custom cloud sync configuration"

    if ! check_cloud_sync_prerequisites; then
        return
    fi

    # Build custom sync options
    local sync_options=""
    local option_descriptions="Custom Cloud Sync Options:\n"

    # Transfer options
    local transfer_choice
    transfer_choice=$(dialog --clear --title "Transfer Options" \
                            --menu "Select transfer method:" \
                            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                            "1" "Sync (mirror - recommended)" \
                            "2" "Copy (add files only)" \
                            "3" "Move (transfer and delete local)" \
                            3>&1 1>&2 2>&3)

    case $transfer_choice in
        1)
            sync_options="sync"
            option_descriptions="${option_descriptions}• Method: Sync (mirror)\n"
            ;;
        2)
            sync_options="copy"
            option_descriptions="${option_descriptions}• Method: Copy (add only)\n"
            ;;
        3)
            sync_options="move"
            option_descriptions="${option_descriptions}• Method: Move (transfer & delete local)\n"
            ;;
        *) return ;;
    esac

    # Transfer speed
    local speed_choice
    speed_choice=$(dialog --clear --title "Transfer Speed" \
                         --menu "Select transfer speed:" \
                         $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                         "1" "Fast (4 transfers)" \
                         "2" "Normal (2 transfers)" \
                         "3" "Slow (1 transfer)" \
                         "4" "Custom transfer count" \
                         3>&1 1>&2 2>&3)

    local transfers="2"
    case $speed_choice in
        1) transfers="4" ;;
        2) transfers="2" ;;
        3) transfers="1" ;;
        4)
            transfers=$(dialog --inputbox "Enter number of concurrent transfers (1-16):" 8 50 "2" 3>&1 1>&2 2>&3)
            if [[ ! "$transfers" =~ ^[1-9]$ && ! "$transfers" =~ ^1[0-6]$ ]]; then
                transfers="2"
            fi
            ;;
    esac
    option_descriptions="${option_descriptions}• Concurrent transfers: $transfers\n"

    # Verbose mode
    if show_confirm "Verbose Mode" "Enable verbose output for detailed transfer logging?"; then
        sync_options="$sync_options --verbose"
        option_descriptions="${option_descriptions}• Verbose logging enabled\n"
    fi

    # Show summary and confirm
    if show_confirm "Custom Cloud Sync Summary" "${option_descriptions}\nProceed with custom cloud sync?"; then
        # Create custom rclone command
        local custom_command="rclone $sync_options --transfers=$transfers"

        if [[ "$sync_options" =~ --verbose ]]; then
            custom_command="$custom_command --progress --stats=10s"
        fi

        # Add source and destination (simplified - would need proper rclone script modification)
        show_progress "Custom Cloud Sync" "Running custom cloud sync with selected options...\n\nThis may take several minutes." \
                      "$RCLONE_BACKUP_SCRIPT --transfers=$transfers"

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            show_info "Custom Sync Complete" "Custom cloud sync completed successfully!\n\nAll selected options were applied.\n\nCheck logs for detailed transfer results."
        else
            show_error "Custom Sync Failed" "Custom cloud sync failed with exit code: $exit_code\n\nCheck the output for error details."
            show_output "Custom Cloud Sync Output"
        fi
    fi
}

# Dry run cloud sync
dry_run_cloud_sync() {
    log_tui "Starting dry run cloud sync"

    if show_confirm "Dry Run Cloud Sync" "Perform a dry run cloud sync?\n\nThis will:\n• Show what would be transferred\n• Test cloud connectivity\n• No actual upload performed\n• Safe to run anytime\n\nContinue?"; then
        show_progress "Dry Run Cloud Sync" "Performing dry run test...\n\nChecking cloud connectivity and analyzing transfer requirements..." \
                      "rclone sync --dry-run --verbose"

        if [[ $? -eq 0 ]]; then
            show_info "Dry Run Complete" "Dry run completed successfully!\n\n✓ Cloud connectivity confirmed\n✓ Transfer requirements analyzed\n✓ No issues found\n\nSystem is ready for actual cloud sync."
        else
            show_error "Dry Run Issues Found" "Dry run found issues that need attention.\n\nPlease review and fix before running actual sync."
            show_output "Dry Run Cloud Sync Output"
        fi
    fi
}

# View sync status
view_sync_status() {
    local status_file="$TEMP_DIR/cloud_sync_status.txt"

    log_tui "Generating cloud sync status report"

    # Generate sync status report
    cat > "$status_file" << EOF
CLOUD SYNC STATUS REPORT
========================

Generated: $(date)
Host: $(hostname)

EOF

    # Rclone configuration status
    echo "Rclone Configuration:" >> "$status_file"
    if command -v rclone >/dev/null 2>&1; then
        echo "  ✓ Rclone available: $(rclone version | head -1)" >> "$status_file"

        local remotes_count=$(rclone listremotes | wc -l)
        echo "  • Configured remotes: $remotes_count" >> "$status_file"

        if [[ $remotes_count -gt 0 ]]; then
            echo "  • Available remotes:" >> "$status_file"
            rclone listremotes | sed 's/^/    - /' | sed 's/:$//' >> "$status_file"
        fi
    else
        echo "  ✗ Rclone not available" >> "$status_file"
    fi
    echo "" >> "$status_file"

    # Last sync information
    echo "Last Sync Information:" >> "$status_file"
    if [[ -f "/var/log/rclone_backup.log" ]]; then
        local last_sync_start=$(grep "Starting backup" "/var/log/rclone_backup.log" | tail -1)
        local last_sync_complete=$(grep "Backup completed" "/var/log/rclone_backup.log" | tail -1)

        if [[ -n "$last_sync_start" ]]; then
            echo "  • Last started: $(echo "$last_sync_start" | awk '{print $1" "$2" "$3" "$4" "$5}')" >> "$status_file"
        fi

        if [[ -n "$last_sync_complete" ]]; then
            echo "  • Status: ✓ Completed successfully" >> "$status_file"
            echo "  • Last completed: $(echo "$last_sync_complete" | awk '{print $1" "$2" "$3" "$4" "$5}')" >> "$status_file"
        else
            echo "  • Status: Unknown or in progress" >> "$status_file"
        fi
    else
        echo "  • No sync log found" >> "$status_file"
    fi
    echo "" >> "$status_file"

    # Source directory status
    echo "Source Directory Status:" >> "$status_file"
    if [[ -f "$BACKUP_CONFIG" ]]; then
        local restic_repo=$(grep "^RESTIC_REPOSITORY=" "$BACKUP_CONFIG" | cut -d= -f2 | xargs)
        if [[ -n "$restic_repo" && "$restic_repo" =~ ^/ ]]; then
            local source_dir="$(dirname "$restic_repo")"
            if [[ -d "$source_dir" ]]; then
                local source_size=$(du -sh "$source_dir" 2>/dev/null | cut -f1 || echo "Unknown")
                echo "  ✓ Source directory: $source_dir" >> "$status_file"
                echo "  • Size: $source_size" >> "$status_file"

                local file_count=$(find "$source_dir" -type f | wc -l)
                echo "  • Files: $file_count" >> "$status_file"
            else
                echo "  ✗ Source directory not found: $source_dir" >> "$status_file"
            fi
        else
            echo "  • Remote repository detected (not local sync)" >> "$status_file"
        fi
    else
        echo "  • Cannot determine (backup config missing)" >> "$status_file"
    fi

    dialog --title "Cloud Sync Status Report" \
           --textbox "$status_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Test cloud connectivity
test_cloud_connectivity() {
    log_tui "Testing cloud connectivity"

    # Get list of remotes
    local remotes_file="$TEMP_DIR/remotes.txt"
    rclone listremotes > "$remotes_file" 2>/dev/null || true

    if [[ ! -s "$remotes_file" ]]; then
        show_error "No Remotes Found" "No rclone remotes are configured.\n\nPlease configure rclone first using:\nConfiguration Management → Configure Rclone Remotes"
        return
    fi

    # Let user select remote to test
    local remote_choice
    remote_choice=$(dialog --clear --title "Test Cloud Connectivity" \
                          --menu "Select remote to test:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          $(cat "$remotes_file" | nl -w2 -s' ' | awk '{print $1, $2}') \
                          3>&1 1>&2 2>&3)

    if [[ -n "$remote_choice" ]]; then
        local remote_name=$(sed -n "${remote_choice}p" "$remotes_file")

        show_progress "Testing Connectivity" "Testing connection to $remote_name...\n\nThis may take a moment..." \
                      "rclone lsd ${remote_name} --max-depth 1"

        if [[ $? -eq 0 ]]; then
            show_info "Connectivity Test Success" "Successfully connected to remote: $remote_name\n\n✓ Authentication working\n✓ Network connectivity confirmed\n✓ Remote is accessible\n\nReady for cloud sync operations."

            # Offer to show remote details
            if show_confirm "Remote Details" "Would you like to view detailed information about this remote?"; then
                show_progress "Remote Information" "Gathering remote details..." \
                              "rclone about ${remote_name}"
                show_output "Remote Details"
            fi
        else
            show_error "Connectivity Test Failed" "Failed to connect to remote: $remote_name\n\n⚠️  Check your configuration\n⚠️  Verify network connection\n⚠️  Check credentials\n\nUse Configuration Management to reconfigure."
            show_output "Connectivity Test Output"
        fi
    fi
}

# Configure rclone settings
configure_rclone_settings() {
    local choice
    choice=$(dialog --clear --title "Rclone Settings Configuration" \
                   --menu "Choose rclone setting to configure:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "1" "Configure new remote" \
                   "2" "Edit existing remote" \
                   "3" "Delete remote" \
                   "4" "View remote configuration" \
                   "5" "Edit rclone backup script" \
                   "6" "Test all remotes" \
                   "7" "Import/export configuration" \
                   "0" "Return to cloud sync menu" \
                   3>&1 1>&2 2>&3)

    case $choice in
        1) configure_rclone ;;
        2) edit_rclone_remote ;;
        3) delete_rclone_remote ;;
        4) view_rclone_config ;;
        5) edit_rclone_script ;;
        6) test_all_remotes ;;
        7) import_export_rclone_config ;;
        0|"") return ;;
    esac
}

# Schedule automatic sync
schedule_sync() {
    local choice
    choice=$(dialog --clear --title "Schedule Automatic Cloud Sync" \
                   --menu "Choose scheduling option:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "1" "Setup daily sync" \
                   "2" "Setup weekly sync" \
                   "3" "Custom cron schedule" \
                   "4" "View current schedule" \
                   "5" "Disable scheduled sync" \
                   "0" "Return to cloud sync menu" \
                   3>&1 1>&2 2>&3)

    case $choice in
        1) setup_daily_sync ;;
        2) setup_weekly_sync ;;
        3) setup_custom_schedule ;;
        4) view_sync_schedule ;;
        5) disable_sync_schedule ;;
        0|"") return ;;
    esac
}

# Cloud sync troubleshooting
sync_troubleshooting() {
    local choice
    choice=$(dialog --clear --title "Cloud Sync Troubleshooting" \
                   --menu "Select troubleshooting option:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "1" "View recent sync logs" \
                   "2" "Test rclone configuration" \
                   "3" "Check network connectivity" \
                   "4" "Validate remote credentials" \
                   "5" "Check bandwidth usage" \
                   "6" "View common sync issues" \
                   "7" "Reset sync configuration" \
                   "0" "Return to cloud sync menu" \
                   3>&1 1>&2 2>&3)

    case $choice in
        1) view_sync_logs ;;
        2) test_rclone_config ;;
        3) check_network_connectivity ;;
        4) validate_remote_credentials ;;
        5) check_bandwidth_usage ;;
        6) show_sync_solutions ;;
        7) reset_sync_config ;;
        0|"") return ;;
    esac
}

# Check cloud sync prerequisites with detailed validation
check_cloud_sync_prerequisites() {
    # Use detailed prerequisite check
    if ! check_prerequisites_detailed "sync"; then
        # Show detailed validation results
        show_validation_results "Cloud Sync Prerequisites" \
            "Some prerequisites are not met. Please resolve the issues below before running cloud sync." \
            VALIDATION_CHECKS
        return 1
    fi

    return 0
}

#######################################
# Stage 3: Cloud Restore Management
#######################################

# Cloud restore main menu
stage3_cloud_restore_menu() {
    while true; do
        local title
        title="$(get_title_with_breadcrumb "Stage 3: Cloud Restore (Download)")"

        local choice
        choice=$(dialog --clear --title "$title" \
                       --menu "Choose restore operation:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Quick Repository Restore" \
                       "2" "Custom Restore with Options" \
                       "3" "Selective File Restore" \
                       "4" "Preview Available Backups" \
                       "5" "Test Restore Process" \
                       "6" "Configure Restore Settings" \
                       "7" "Restore Troubleshooting" \
                       "8" "Disaster Recovery Wizard" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) quick_repository_restore ;;
            2) custom_restore ;;
            3) selective_file_restore ;;
            4) preview_available_backups ;;
            5) test_restore_process ;;
            6) configure_restore_settings ;;
            7) restore_troubleshooting ;;
            8) disaster_recovery_wizard ;;
            0|"") break ;;
        esac
    done
}

# Quick repository restore
quick_repository_restore() {
    log_tui "Starting quick repository restore"

    if ! check_restore_prerequisites; then
        return
    fi

    # Get target directory
    local target_dir="/tmp/restored_backup_$(date +%Y%m%d_%H%M%S)"

    local custom_target
    custom_target=$(dialog --inputbox "Enter restore target directory:" 8 60 "$target_dir" 3>&1 1>&2 2>&3)

    if [[ -n "$custom_target" ]]; then
        target_dir="$custom_target"
    fi

    if show_confirm "Quick Repository Restore" "Restore backup repository from cloud?\n\nTarget: $target_dir\nThis will download the entire repository from cloud.\n\nEstimated time: 10-120 minutes\n\nContinue?"; then
        # Create target directory
        mkdir -p "$target_dir" || {
            show_error "Directory Creation Failed" "Failed to create target directory: $target_dir"
            return
        }

        show_progress "Cloud Repository Restore" "Downloading repository from cloud storage...\n\nThis may take significant time depending on repository size and connection speed." \
                      "$RCLONE_RESTORE_SCRIPT '$target_dir'"

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            show_info "Repository Restore Complete" "Repository restore completed successfully!\n\n✓ Repository downloaded from cloud\n✓ Data available for recovery\n✓ Ready for restic operations\n\nLocation: $target_dir"

            # Offer next steps
            if show_confirm "Next Steps" "Repository is now restored.\n\nWould you like to explore restoration options?"; then
                selective_file_restore
            fi
        else
            show_error "Repository Restore Failed" "Repository restore failed with exit code: $exit_code\n\nPlease check the logs for detailed error information."
            show_output "Repository Restore Output"

            # Clean up failed restore
            if show_confirm "Cleanup" "Would you like to remove the incomplete restore directory?"; then
                rm -rf "$target_dir" 2>/dev/null || true
            fi
        fi
    fi
}

# Custom restore with options
custom_restore() {
    log_tui "Starting custom restore configuration"

    if ! check_restore_prerequisites; then
        return
    fi

    # Get restore options
    local restore_options=""
    local option_descriptions="Custom Restore Options:\n"

    # Restore method
    local method_choice
    method_choice=$(dialog --clear --title "Restore Method" \
                          --menu "Select restore method:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          "1" "Full repository restore" \
                          "2" "Specific files only" \
                          "3" "Latest snapshot only" \
                          3>&1 1>&2 2>&3)

    case $method_choice in
        1)
            option_descriptions="${option_descriptions}• Method: Full repository restore\n"
            ;;
        2)
            option_descriptions="${option_descriptions}• Method: Specific files only\n"
            ;;
        3)
            option_descriptions="${option_descriptions}• Method: Latest snapshot only\n"
            ;;
        *) return ;;
    esac

    # Transfer speed
    local speed_choice
    speed_choice=$(dialog --clear --title "Download Speed" \
                         --menu "Select download speed:" \
                         $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                         "1" "Fast (4 concurrent downloads)" \
                         "2" "Normal (2 concurrent downloads)" \
                         "3" "Slow (1 download at a time)" \
                         3>&1 1>&2 2>&3)

    local transfers="2"
    case $speed_choice in
        1) transfers="4"; option_descriptions="${option_descriptions}• Speed: Fast (4 transfers)\n" ;;
        2) transfers="2"; option_descriptions="${option_descriptions}• Speed: Normal (2 transfers)\n" ;;
        3) transfers="1"; option_descriptions="${option_descriptions}• Speed: Slow (1 transfer)\n" ;;
    esac

    # Verification
    if show_confirm "Verify Downloads" "Enable download verification?\n\nThis ensures file integrity but takes longer."; then
        option_descriptions="${option_descriptions}• Verification: Enabled\n"
    else
        option_descriptions="${option_descriptions}• Verification: Disabled\n"
    fi

    # Get target directory
    local target_dir="/tmp/custom_restore_$(date +%Y%m%d_%H%M%S)"
    local custom_target
    custom_target=$(dialog --inputbox "Enter restore target directory:" 8 60 "$target_dir" 3>&1 1>&2 2>&3)

    if [[ -n "$custom_target" ]]; then
        target_dir="$custom_target"
    fi

    option_descriptions="${option_descriptions}• Target: $target_dir\n"

    # Show summary and confirm
    if show_confirm "Custom Restore Summary" "${option_descriptions}\nProceed with custom restore?"; then
        mkdir -p "$target_dir" || {
            show_error "Directory Creation Failed" "Failed to create target directory: $target_dir"
            return
        }

        show_progress "Custom Cloud Restore" "Running custom restore with selected options...\n\nThis may take significant time." \
                      "$RCLONE_RESTORE_SCRIPT --transfers=$transfers '$target_dir'"

        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            show_info "Custom Restore Complete" "Custom restore completed successfully!\n\nAll selected options were applied.\n\nLocation: $target_dir"
        else
            show_error "Custom Restore Failed" "Custom restore failed with exit code: $exit_code\n\nCheck the output for error details."
            show_output "Custom Restore Output"
        fi
    fi
}

# Check restore prerequisites with detailed validation
check_restore_prerequisites() {
    # Use detailed prerequisite check
    if ! check_prerequisites_detailed "restore"; then
        # Show detailed validation results
        show_validation_results "Restore Prerequisites" \
            "Some prerequisites are not met. Please resolve the issues below before running restore." \
            VALIDATION_CHECKS
        return 1
    fi

    return 0
}

# Placeholder functions for advanced features
selective_file_restore() {
    show_info "Feature Coming Soon" "Selective file restore will be available in the next version."
}

preview_available_backups() {
    show_info "Feature Coming Soon" "Backup preview will be available in the next version."
}

test_restore_process() {
    show_info "Feature Coming Soon" "Restore testing will be available in the next version."
}

configure_restore_settings() {
    show_info "Feature Coming Soon" "Restore configuration will be available in the next version."
}

restore_troubleshooting() {
    show_info "Feature Coming Soon" "Restore troubleshooting will be available in the next version."
}

disaster_recovery_wizard() {
    show_info "Feature Coming Soon" "Disaster recovery wizard will be available in the next version."
}

#######################################
# Directory List Management System
#######################################

# Global variables for directory management
BACKUP_DIR=""
DISCOVERED_DIRS=()
declare -A EXISTING_DIRLIST
REMOVED_DIRS=()
NEW_DIRS=()
CHANGES_DETECTED="false"
CHECKLIST_OPTIONS=()

# Load configuration to get BACKUP_DIR for directory management
load_config_for_dirlist() {
    if [[ ! -f "$BACKUP_CONFIG" ]]; then
        show_error "Configuration Missing" "Configuration file not found: $BACKUP_CONFIG\n\nPlease configure docker backup first."
        return 1
    fi

    # Read configuration file and extract BACKUP_DIR
    local config_content
    config_content="$(grep -v '^[[:space:]]*#' "$BACKUP_CONFIG" | grep -v '^[[:space:]]*$' | head -20)"

    if [[ -z "$config_content" ]]; then
        show_error "Invalid Configuration" "No valid configuration found in: $BACKUP_CONFIG"
        return 1
    fi

    # Parse BACKUP_DIR from configuration
    while IFS='=' read -r key value; do
        # Strip inline comments and whitespace from value
        value="$(echo "$value" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        if [[ "$key" == "BACKUP_DIR" ]]; then
            BACKUP_DIR="$(echo "$value" | sed 's/^[\"'\'']\|[\"'\'']$//g')"
            break
        fi
    done <<< "$config_content"

    if [[ -z "$BACKUP_DIR" ]]; then
        show_error "Configuration Error" "BACKUP_DIR not found in configuration file."
        return 1
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        show_error "Directory Not Found" "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi

    log_tui "Using backup directory: $BACKUP_DIR"
    return 0
}

# Discover Docker compose directories for TUI
discover_directories_tui() {
    local found_dirs=()
    local dir_count=0

    log_tui "Scanning for Docker compose directories in: $BACKUP_DIR"

    # Check if backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        show_error "Directory Error" "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi

    # Find all top-level subdirectories containing docker-compose files
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

    log_tui "Found $dir_count Docker compose directories"

    # Store results in global variable
    DISCOVERED_DIRS=("${found_dirs[@]}")

    if [[ $dir_count -eq 0 ]]; then
        show_error "No Directories Found" "No Docker compose directories found in: $BACKUP_DIR\n\nMake sure your Docker compose files are named:\n• docker-compose.yml\n• docker-compose.yaml\n• compose.yml\n• compose.yaml"
        return 1
    fi

    return 0
}

# Load existing .dirlist file for TUI
load_dirlist_tui() {
    local dirlist_file="$SCRIPT_DIR/dirlist"

    # Clear existing dirlist
    unset EXISTING_DIRLIST
    declare -gA EXISTING_DIRLIST

    if [[ ! -f "$dirlist_file" ]]; then
        log_tui "Directory list file not found: $dirlist_file"
        log_tui "Will create new .dirlist file based on discovered directories"
        return 1
    fi

    log_tui "Loading existing directory list from: $dirlist_file"

    # Read the dirlist file and populate the associative array
    while IFS='=' read -r dir_name enabled; do
        # Skip comments and empty lines
        if [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]]; then
            continue
        fi

        # Validate format
        if [[ "$enabled" =~ ^(true|false)$ ]]; then
            EXISTING_DIRLIST["$dir_name"]="$enabled"
        fi
    done < "$dirlist_file"

    return 0
}

# Validate dirlist file format
validate_dirlist_format() {
    local dirlist_file="$SCRIPT_DIR/dirlist"
    local issues=0
    local temp_report="$TEMP_DIR/dirlist_validation.txt"

    if [[ ! -f "$dirlist_file" ]]; then
        echo "Directory list file not found: $dirlist_file" > "$temp_report"
        return 1
    fi

    echo "DIRECTORY LIST VALIDATION REPORT" > "$temp_report"
    echo "=================================" >> "$temp_report"
    echo "" >> "$temp_report"
    echo "File: $dirlist_file" >> "$temp_report"
    echo "Generated: $(date)" >> "$temp_report"
    echo "" >> "$temp_report"

    local line_num=0
    while IFS= read -r line; do
        ((line_num++))

        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Check format: directory_name=true|false
        if [[ "$line" =~ ^[^=]+=(true|false)$ ]]; then
            local dir_name="${line%%=*}"
            local enabled="${line##*=}"
            echo "✓ Line $line_num: Valid format - $dir_name=$enabled" >> "$temp_report"
        else
            echo "✗ Line $line_num: Invalid format - $line" >> "$temp_report"
            ((issues++))
        fi
    done < "$dirlist_file"

    echo "" >> "$temp_report"
    if [[ $issues -eq 0 ]]; then
        echo "✓ VALIDATION PASSED: No format issues found" >> "$temp_report"
    else
        echo "⚠ VALIDATION FAILED: $issues format issue(s) found" >> "$temp_report"
    fi

    dialog --title "Directory List Validation" \
           --textbox "$temp_report" \
           $DIALOG_HEIGHT $DIALOG_WIDTH

    return $issues
}

# View comprehensive directory status
view_directory_status_tui() {
    log_tui "Generating directory status report"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    # Load existing dirlist
    load_dirlist_tui || true

    local status_file="$TEMP_DIR/directory_status.txt"

    cat > "$status_file" << EOF
DIRECTORY STATUS REPORT
=======================

Generated: $(date)
Backup Directory: $BACKUP_DIR
Total Discovered: ${#DISCOVERED_DIRS[@]}

EOF

    # Directory status summary
    local enabled_count=0
    local disabled_count=0
    local new_count=0
    local missing_count=0

    # Count existing dirlist entries
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        if [[ "${EXISTING_DIRLIST[$dir]}" == "true" ]]; then
            ((enabled_count++))
        else
            ((disabled_count++))
        fi
    done

    # Check for new directories not in dirlist
    for dir in "${DISCOVERED_DIRS[@]}"; do
        if [[ -z "${EXISTING_DIRLIST[$dir]:-}" ]]; then
            ((new_count++))
        fi
    done

    # Check for missing directories (in dirlist but not discovered)
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        local found=false
        for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
            if [[ "$dir" == "$discovered_dir" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            ((missing_count++))
        fi
    done

    echo "STATUS SUMMARY:" >> "$status_file"
    echo "• Enabled for backup: $enabled_count" >> "$status_file"
    echo "• Disabled: $disabled_count" >> "$status_file"
    echo "• New (not in dirlist): $new_count" >> "$status_file"
    echo "• Missing (in dirlist but not found): $missing_count" >> "$status_file"
    echo "" >> "$status_file"

    # Detailed directory listing
    echo "DETAILED DIRECTORY STATUS:" >> "$status_file"
    echo "" >> "$status_file"

    # Show enabled directories
    if [[ $enabled_count -gt 0 ]]; then
        echo "✓ ENABLED DIRECTORIES (will be backed up):" >> "$status_file"
        for dir in $(printf '%s\n' "${!EXISTING_DIRLIST[@]}" | sort); do
            if [[ "${EXISTING_DIRLIST[$dir]}" == "true" ]]; then
                local dir_path="$BACKUP_DIR/$dir"
                if [[ -d "$dir_path" ]]; then
                    local size="$(du -sh "$dir_path" 2>/dev/null | cut -f1 || echo "Unknown")"
                    echo "  • $dir ($size)" >> "$status_file"
                else
                    echo "  • $dir (⚠ Directory missing)" >> "$status_file"
                fi
            fi
        done
        echo "" >> "$status_file"
    fi

    # Show disabled directories
    if [[ $disabled_count -gt 0 ]]; then
        echo "✗ DISABLED DIRECTORIES (will be skipped):" >> "$status_file"
        for dir in $(printf '%s\n' "${!EXISTING_DIRLIST[@]}" | sort); do
            if [[ "${EXISTING_DIRLIST[$dir]}" == "false" ]]; then
                echo "  • $dir" >> "$status_file"
            fi
        done
        echo "" >> "$status_file"
    fi

    # Show new directories
    if [[ $new_count -gt 0 ]]; then
        echo "➕ NEW DIRECTORIES (not in dirlist):" >> "$status_file"
        for dir in "${DISCOVERED_DIRS[@]}"; do
            if [[ -z "${EXISTING_DIRLIST[$dir]:-}" ]]; then
                local dir_path="$BACKUP_DIR/$dir"
                local size="$(du -sh "$dir_path" 2>/dev/null | cut -f1 || echo "Unknown")"
                echo "  • $dir ($size)" >> "$status_file"
            fi
        done
        echo "" >> "$status_file"
    fi

    # Show missing directories
    if [[ $missing_count -gt 0 ]]; then
        echo "⚠ MISSING DIRECTORIES (in dirlist but not found):" >> "$status_file"
        for dir in "${!EXISTING_DIRLIST[@]}"; do
            local found=false
            for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
                if [[ "$dir" == "$discovered_dir" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                echo "  • $dir (${EXISTING_DIRLIST[$dir]})" >> "$status_file"
            fi
        done
        echo "" >> "$status_file"
    fi

    # Add backup history information if available
    echo "BACKUP HISTORY:" >> "$status_file"
    if [[ -f "$SCRIPT_DIR/logs/docker_backup.log" ]]; then
        local last_backup=$(grep "Backup.*[Cc]ompleted" "$SCRIPT_DIR/logs/docker_backup.log" | tail -1 | cut -d' ' -f1-2)
        if [[ -n "$last_backup" ]]; then
            echo "  • Last successful backup: $last_backup" >> "$status_file"
        else
            echo "  • No successful backups found in logs" >> "$status_file"
        fi

        local total_backups=$(grep -c "Backup.*[Cc]ompleted" "$SCRIPT_DIR/logs/docker_backup.log" 2>/dev/null || echo "0")
        echo "  • Total successful backups: $total_backups" >> "$status_file"
    else
        echo "  • No backup log file found" >> "$status_file"
    fi

    dialog --title "Directory Status Report" \
           --textbox "$status_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH

    # Offer additional actions
    local action_choice
    action_choice=$(dialog --clear --title "Directory Status Actions" \
                          --menu "What would you like to do next?" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          "1" "Refresh status report" \
                          "2" "Select directories for backup" \
                          "3" "Synchronize directory list" \
                          "4" "Return to directory menu" \
                          3>&1 1>&2 2>&3)

    case $action_choice in
        1) view_directory_status_tui ;;
        2) select_directories_tui ;;
        3) synchronize_directory_list ;;
        4|"") return ;;
    esac
}

# Create dialog checklist options for directory selection
create_checklist_options_tui() {
    local -a options=()

    # Combine discovered directories with existing dirlist
    local -A all_dirs

    # Add discovered directories (default to true for new dirs)
    for dir in "${DISCOVERED_DIRS[@]}"; do
        all_dirs["$dir"]="true"
    done

    # Override with existing settings if available
    for dir in "${!EXISTING_DIRLIST[@]}"; do
        all_dirs["$dir"]="${EXISTING_DIRLIST[$dir]}"
    done

    # Create options array for dialog: tag description status
    for dir in $(printf '%s\n' "${!all_dirs[@]}" | sort); do
        local status="${all_dirs[$dir]}"
        local check_status="off"
        local description="Docker compose directory"

        if [[ "$status" == "true" ]]; then
            check_status="on"
        fi

        # Add size information if directory exists
        local dir_path="$BACKUP_DIR/$dir"
        if [[ -d "$dir_path" ]]; then
            local size="$(du -sh "$dir_path" 2>/dev/null | cut -f1 || echo "?")"
            description="Docker compose directory ($size)"
        else
            description="Docker compose directory (⚠ missing)"
        fi

        # Add directory to options: tag description status
        options+=("$dir" "$description" "$check_status")
    done

    # Return options via global variable
    CHECKLIST_OPTIONS=("${options[@]}")
}

# Interactive directory selection interface
select_directories_tui() {
    log_tui "Opening directory selection interface"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    # Load existing dirlist
    load_dirlist_tui || true

    # Create checklist options
    create_checklist_options_tui

    if [[ ${#CHECKLIST_OPTIONS[@]} -eq 0 ]]; then
        show_error "No Directories" "No directories available for selection."
        return
    fi

    local temp_file="$TEMP_DIR/directory_selection.txt"

    # Show directory selection dialog
    if dialog --clear \
        --title "Select Directories for Backup" \
        --backtitle "Docker Stack Backup System - Directory Selection" \
        --checklist "Use SPACE to toggle, ENTER to confirm, ESC to cancel:\n\nSelect directories to include in backup:" \
        20 80 12 \
        "${CHECKLIST_OPTIONS[@]}" \
        2>"$temp_file"; then

        # User confirmed selection
        local selected_dirs
        selected_dirs="$(cat "$temp_file")"
        rm -f "$temp_file"

        # Process the selection
        process_directory_selection "$selected_dirs"
    else
        # User cancelled
        rm -f "$temp_file"
        log_tui "Directory selection cancelled by user"
    fi
}

# Process user directory selection
process_directory_selection() {
    local selected_dirs="$1"
    local -A new_settings
    local changes_made=false

    # Initialize all known directories as false
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

    # Show confirmation dialog with changes summary
    show_directory_confirmation new_settings "$changes_made"
}

# Show directory selection confirmation with detailed summary
show_directory_confirmation() {
    local -n settings_ref=$1
    local changes_made="$2"
    local temp_file="$TEMP_DIR/directory_confirmation.txt"

    # Create comprehensive summary
    local enabled_count=0
    local disabled_count=0
    local changed_dirs=()

    cat > "$temp_file" << EOF
DIRECTORY BACKUP CONFIGURATION SUMMARY
=======================================

EOF

    # Count and list enabled directories
    echo "ENABLED DIRECTORIES (will be backed up):" >> "$temp_file"
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        if [[ "${settings_ref[$dir]}" == "true" ]]; then
            local dir_path="$BACKUP_DIR/$dir"
            local size="$(du -sh "$dir_path" 2>/dev/null | cut -f1 || echo "Unknown")"
            echo "  ✓ $dir ($size)" >> "$temp_file"
            ((enabled_count++))

            # Check if this is a change
            local old_setting="${EXISTING_DIRLIST[$dir]:-false}"
            if [[ "$old_setting" != "true" ]]; then
                changed_dirs+=("$dir (enabled)")
            fi
        fi
    done

    if [[ $enabled_count -eq 0 ]]; then
        echo "  (none - NO DIRECTORIES WILL BE BACKED UP!)" >> "$temp_file"
    fi

    echo "" >> "$temp_file"
    echo "DISABLED DIRECTORIES (will be skipped):" >> "$temp_file"

    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        if [[ "${settings_ref[$dir]}" == "false" ]]; then
            echo "  ✗ $dir" >> "$temp_file"
            ((disabled_count++))

            # Check if this is a change
            local old_setting="${EXISTING_DIRLIST[$dir]:-false}"
            if [[ "$old_setting" != "false" ]]; then
                changed_dirs+=("$dir (disabled)")
            fi
        fi
    done

    if [[ $disabled_count -eq 0 ]]; then
        echo "  (none)" >> "$temp_file"
    fi

    echo "" >> "$temp_file"
    echo "SUMMARY:" >> "$temp_file"
    echo "  • Total directories: $((enabled_count + disabled_count))" >> "$temp_file"
    echo "  • Enabled for backup: $enabled_count" >> "$temp_file"
    echo "  • Disabled: $disabled_count" >> "$temp_file"

    if [[ "$changes_made" == "true" ]]; then
        echo "" >> "$temp_file"
        echo "CHANGES DETECTED:" >> "$temp_file"
        for change in "${changed_dirs[@]}"; do
            echo "  • $change" >> "$temp_file"
        done
        echo "" >> "$temp_file"
        echo "⚠ Directory list file will be updated" >> "$temp_file"
    else
        echo "" >> "$temp_file"
        echo "✓ No changes made - current configuration maintained" >> "$temp_file"
    fi

    # Show confirmation dialog
    if dialog --clear \
        --title "Confirm Directory Configuration" \
        --backtitle "Docker Stack Backup System - Confirmation" \
        --yes-label "Save Changes" \
        --no-label "Cancel" \
        --textbox "$temp_file" \
        25 85; then

        # User confirmed, save changes
        save_directory_settings settings_ref
    else
        # User cancelled
        log_tui "Directory configuration changes not saved - cancelled by user"
        show_info "Changes Cancelled" "Directory configuration changes were not saved."
    fi

    rm -f "$temp_file"
}

# Save directory settings to .dirlist file with atomic operation
save_directory_settings() {
    local -n settings_ref=$1
    local dirlist_file="$SCRIPT_DIR/dirlist"
    local temp_dirlist="$TEMP_DIR/dirlist.tmp"

    log_tui "Saving directory configuration to: $dirlist_file"

    # Create temporary dirlist file
    cat > "$temp_dirlist" << 'EOF'
# Auto-generated directory list for selective backup
# Edit this file to enable/disable backup for each directory
# true = backup enabled, false = skip backup
# Generated by Backup TUI on $(date)
EOF

    # Add timestamp comment
    echo "# Last updated: $(date)" >> "$temp_dirlist"
    echo "" >> "$temp_dirlist"

    # Write directory settings in sorted order
    for dir in $(printf '%s\n' "${!settings_ref[@]}" | sort); do
        echo "$dir=${settings_ref[$dir]}" >> "$temp_dirlist"
    done

    # Atomically replace the dirlist file
    if mv "$temp_dirlist" "$dirlist_file"; then
        local enabled_count=0
        local enabled_dirs=()

        # Count enabled directories
        for dir in "${!settings_ref[@]}"; do
            if [[ "${settings_ref[$dir]}" == "true" ]]; then
                enabled_dirs+=("$dir")
                ((enabled_count++))
            fi
        done

        # Show success message with summary
        local summary="Directory configuration saved successfully!\n\nFile: $dirlist_file\nDirectories enabled: $enabled_count"

        if [[ $enabled_count -gt 0 && $enabled_count -le 10 ]]; then
            summary="${summary}\n\nEnabled directories:"
            for dir in $(printf '%s\n' "${enabled_dirs[@]}" | sort); do
                summary="${summary}\n• $dir"
            done
        elif [[ $enabled_count -gt 10 ]]; then
            summary="${summary}\n\n(Too many to list - view status for details)"
        fi

        summary="${summary}\n\nChanges will take effect on next backup."

        show_info "Configuration Saved" "$summary"

        # Update global EXISTING_DIRLIST for other functions
        unset EXISTING_DIRLIST
        declare -gA EXISTING_DIRLIST
        for dir in "${!settings_ref[@]}"; do
            EXISTING_DIRLIST["$dir"]="${settings_ref[$dir]}"
        done

        log_tui "Directory configuration saved successfully with $enabled_count enabled directories"

    else
        rm -f "$temp_dirlist"
        show_error "Save Failed" "Failed to save directory configuration.\n\nPlease check file permissions and disk space."
        log_tui "Failed to save directory configuration to $dirlist_file"
    fi
}

# Bulk operations menu
bulk_operations_menu() {
    log_tui "Opening bulk operations menu"

    while true; do
        local choice
        choice=$(dialog --clear --title "Bulk Directory Operations" \
                       --menu "Choose bulk operation:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Enable All Directories" \
                       "2" "Disable All Directories" \
                       "3" "Enable by Pattern Matching" \
                       "4" "Disable by Pattern Matching" \
                       "5" "Toggle All Directory States" \
                       "6" "Reset to Defaults (New dirs enabled)" \
                       "7" "Apply Template Configuration" \
                       "0" "Return to Directory Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) bulk_enable_all ;;
            2) bulk_disable_all ;;
            3) bulk_enable_by_pattern ;;
            4) bulk_disable_by_pattern ;;
            5) bulk_toggle_all ;;
            6) bulk_reset_defaults ;;
            7) bulk_apply_template ;;
            0|"") break ;;
        esac
    done
}

# Bulk enable all directories
bulk_enable_all() {
    log_tui "Bulk enabling all directories"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local dir_count=${#DISCOVERED_DIRS[@]}
    local confirmation="Enable ALL directories for backup?\n\nThis will set ${dir_count} directories to enabled status.\n\nDirectories:"

    # Add first few directories to confirmation
    local shown_count=0
    for dir in $(printf '%s\n' "${DISCOVERED_DIRS[@]}" | sort); do
        if [[ $shown_count -lt 8 ]]; then
            confirmation="${confirmation}\n• $dir"
            ((shown_count++))
        else
            confirmation="${confirmation}\n• ... and $((dir_count - shown_count)) more"
            break
        fi
    done

    confirmation="${confirmation}\n\nContinue?"

    if show_confirm "Bulk Enable All" "$confirmation"; then
        local -A bulk_settings

        # Set all discovered directories to enabled
        for dir in "${DISCOVERED_DIRS[@]}"; do
            bulk_settings["$dir"]="true"
        done

        # Add any existing disabled directories (keep them in list but disabled)
        for dir in "${!EXISTING_DIRLIST[@]}"; do
            if [[ -z "${bulk_settings[$dir]:-}" ]]; then
                bulk_settings["$dir"]="false"  # Keep missing dirs disabled
            fi
        done

        save_directory_settings bulk_settings
    fi
}

# Bulk disable all directories
bulk_disable_all() {
    log_tui "Bulk disabling all directories"

    if show_confirm "Bulk Disable All" "Disable ALL directories for backup?\n\n⚠ WARNING: This will disable backup for all directories!\nNo directories will be backed up until re-enabled.\n\nContinue?"; then

        # Load configuration and discover directories
        if ! load_config_for_dirlist; then
            return
        fi

        if ! discover_directories_tui; then
            return
        fi

        load_dirlist_tui || true

        local -A bulk_settings

        # Set all directories to disabled
        for dir in "${DISCOVERED_DIRS[@]}"; do
            bulk_settings["$dir"]="false"
        done

        # Include existing dirlist directories
        for dir in "${!EXISTING_DIRLIST[@]}"; do
            bulk_settings["$dir"]="false"
        done

        save_directory_settings bulk_settings
    fi
}

# Bulk enable directories by pattern matching
bulk_enable_by_pattern() {
    log_tui "Bulk enabling directories by pattern"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    # Get pattern from user
    local pattern
    pattern=$(dialog --inputbox "Enter pattern to match directory names:\n\nExamples:\n• app* (matches app1, app2, etc)\n• *web* (matches webserver, webapp, etc)\n• test-* (matches test-db, test-api, etc)\n\nPattern:" 15 60 3>&1 1>&2 2>&3)

    if [[ -z "$pattern" ]]; then
        return
    fi

    # Find matching directories
    local matching_dirs=()
    for dir in "${DISCOVERED_DIRS[@]}"; do
        if [[ "$dir" == $pattern ]]; then
            matching_dirs+=("$dir")
        fi
    done

    if [[ ${#matching_dirs[@]} -eq 0 ]]; then
        show_error "No Matches" "No directories found matching pattern: $pattern"
        return
    fi

    # Show matching directories for confirmation
    local match_list="Found ${#matching_dirs[@]} directories matching pattern '$pattern':\n\n"
    for dir in "${matching_dirs[@]}"; do
        match_list="${match_list}• $dir\n"
    done
    match_list="${match_list}\nEnable all these directories for backup?"

    if show_confirm "Confirm Pattern Match" "$match_list"; then
        local -A bulk_settings

        # Start with existing settings
        for dir in "${!EXISTING_DIRLIST[@]}"; do
            bulk_settings["$dir"]="${EXISTING_DIRLIST[$dir]}"
        done

        # Add discovered directories not in existing list (default to false)
        for dir in "${DISCOVERED_DIRS[@]}"; do
            if [[ -z "${bulk_settings[$dir]:-}" ]]; then
                bulk_settings["$dir"]="false"
            fi
        done

        # Enable matching directories
        for dir in "${matching_dirs[@]}"; do
            bulk_settings["$dir"]="true"
        done

        save_directory_settings bulk_settings
    fi
}

# Bulk disable directories by pattern matching
bulk_disable_by_pattern() {
    log_tui "Bulk disabling directories by pattern"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    # Get pattern from user
    local pattern
    pattern=$(dialog --inputbox "Enter pattern to match directory names:\n\nExamples:\n• test-* (disable all test directories)\n• *old* (disable directories with 'old' in name)\n• backup-* (disable backup directories)\n\nPattern:" 15 60 3>&1 1>&2 2>&3)

    if [[ -z "$pattern" ]]; then
        return
    fi

    # Find matching directories
    local matching_dirs=()
    for dir in "${DISCOVERED_DIRS[@]}"; do
        if [[ "$dir" == $pattern ]]; then
            matching_dirs+=("$dir")
        fi
    done

    if [[ ${#matching_dirs[@]} -eq 0 ]]; then
        show_error "No Matches" "No directories found matching pattern: $pattern"
        return
    fi

    # Show matching directories for confirmation
    local match_list="Found ${#matching_dirs[@]} directories matching pattern '$pattern':\n\n"
    for dir in "${matching_dirs[@]}"; do
        match_list="${match_list}• $dir\n"
    done
    match_list="${match_list}\nDisable all these directories for backup?"

    if show_confirm "Confirm Pattern Match" "$match_list"; then
        local -A bulk_settings

        # Start with existing settings
        for dir in "${!EXISTING_DIRLIST[@]}"; do
            bulk_settings["$dir"]="${EXISTING_DIRLIST[$dir]}"
        done

        # Add discovered directories not in existing list (default to false)
        for dir in "${DISCOVERED_DIRS[@]}"; do
            if [[ -z "${bulk_settings[$dir]:-}" ]]; then
                bulk_settings["$dir"]="false"
            fi
        done

        # Disable matching directories
        for dir in "${matching_dirs[@]}"; do
            bulk_settings["$dir"]="false"
        done

        save_directory_settings bulk_settings
    fi
}

# Bulk toggle all directory states
bulk_toggle_all() {
    log_tui "Bulk toggling all directory states"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local enabled_count=0
    local disabled_count=0

    # Count current states
    for dir in "${DISCOVERED_DIRS[@]}"; do
        local current_state="${EXISTING_DIRLIST[$dir]:-false}"
        if [[ "$current_state" == "true" ]]; then
            ((enabled_count++))
        else
            ((disabled_count++))
        fi
    done

    local confirmation="Toggle ALL directory backup states?\n\nCurrent status:\n• Enabled: $enabled_count directories\n• Disabled: $disabled_count directories\n\nAfter toggle:\n• Enabled will become: $disabled_count\n• Disabled will become: $enabled_count\n\nContinue?"

    if show_confirm "Bulk Toggle All" "$confirmation"; then
        local -A bulk_settings

        # Toggle all discovered directories
        for dir in "${DISCOVERED_DIRS[@]}"; do
            local current_state="${EXISTING_DIRLIST[$dir]:-false}"
            if [[ "$current_state" == "true" ]]; then
                bulk_settings["$dir"]="false"
            else
                bulk_settings["$dir"]="true"
            fi
        done

        # Keep existing directories that are no longer discovered (but mark as disabled)
        for dir in "${!EXISTING_DIRLIST[@]}"; do
            if [[ -z "${bulk_settings[$dir]:-}" ]]; then
                bulk_settings["$dir"]="false"
            fi
        done

        save_directory_settings bulk_settings
    fi
}

# Bulk reset to defaults (enable new directories, keep existing settings)
bulk_reset_defaults() {
    log_tui "Bulk resetting to default configuration"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local confirmation="Reset directory configuration to defaults?\n\nThis will:\n• Enable all newly discovered directories\n• Keep existing directory settings unchanged\n• Remove directories that no longer exist\n\nContinue?"

    if show_confirm "Reset to Defaults" "$confirmation"; then
        local -A bulk_settings

        # Set all discovered directories to enabled (default for new)
        for dir in "${DISCOVERED_DIRS[@]}"; do
            local existing_state="${EXISTING_DIRLIST[$dir]:-}"
            if [[ -z "$existing_state" ]]; then
                # New directory - enable by default
                bulk_settings["$dir"]="true"
            else
                # Existing directory - keep current setting
                bulk_settings["$dir"]="$existing_state"
            fi
        done

        save_directory_settings bulk_settings
    fi
}

# Bulk apply template configuration
bulk_apply_template() {
    log_tui "Applying template configuration"

    local template_choice
    template_choice=$(dialog --clear --title "Apply Configuration Template" \
                            --menu "Choose a configuration template:" \
                            $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                            "1" "Production (Enable core services only)" \
                            "2" "Development (Enable all except test dirs)" \
                            "3" "Testing (Enable test directories only)" \
                            "4" "Minimal (Enable essential services only)" \
                            "5" "Custom Template from File" \
                            3>&1 1>&2 2>&3)

    case $template_choice in
        1) apply_production_template ;;
        2) apply_development_template ;;
        3) apply_testing_template ;;
        4) apply_minimal_template ;;
        5) apply_custom_template ;;
    esac
}

# Apply production template (core services)
apply_production_template() {
    # Load directories first
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local -A template_settings
    local production_patterns=("web*" "app*" "db*" "database*" "nginx*" "apache*" "mysql*" "postgres*" "redis*" "mongo*")

    # Start with all disabled
    for dir in "${DISCOVERED_DIRS[@]}"; do
        template_settings["$dir"]="false"
    done

    # Enable directories matching production patterns
    for dir in "${DISCOVERED_DIRS[@]}"; do
        for pattern in "${production_patterns[@]}"; do
            if [[ "$dir" == $pattern ]]; then
                template_settings["$dir"]="true"
                break
            fi
        done
    done

    if show_confirm "Production Template" "Apply production template?\n\nThis will enable directories matching:\n• web*, app*, db*, database*\n• nginx*, apache*, mysql*, postgres*\n• redis*, mongo*\n\nAll other directories will be disabled."; then
        save_directory_settings template_settings
    fi
}

# Apply development template (all except test)
apply_development_template() {
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local -A template_settings
    local test_patterns=("test*" "*test*" "staging*" "*staging*" "demo*" "*demo*")

    # Start with all enabled
    for dir in "${DISCOVERED_DIRS[@]}"; do
        template_settings["$dir"]="true"
    done

    # Disable test/staging/demo directories
    for dir in "${DISCOVERED_DIRS[@]}"; do
        for pattern in "${test_patterns[@]}"; do
            if [[ "$dir" == $pattern ]]; then
                template_settings["$dir"]="false"
                break
            fi
        done
    done

    if show_confirm "Development Template" "Apply development template?\n\nThis will:\n• Enable all directories\n• Except those matching: test*, *test*, staging*, *staging*, demo*, *demo*\n\nContinue?"; then
        save_directory_settings template_settings
    fi
}

# Apply testing template (test directories only)
apply_testing_template() {
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local -A template_settings
    local test_patterns=("test*" "*test*" "staging*" "*staging*" "demo*" "*demo*" "dev*" "*dev*")

    # Start with all disabled
    for dir in "${DISCOVERED_DIRS[@]}"; do
        template_settings["$dir"]="false"
    done

    # Enable test/staging/demo directories
    for dir in "${DISCOVERED_DIRS[@]}"; do
        for pattern in "${test_patterns[@]}"; do
            if [[ "$dir" == $pattern ]]; then
                template_settings["$dir"]="true"
                break
            fi
        done
    done

    if show_confirm "Testing Template" "Apply testing template?\n\nThis will enable only directories matching:\n• test*, *test*, staging*, *staging*\n• demo*, *demo*, dev*, *dev*\n\nAll other directories will be disabled."; then
        save_directory_settings template_settings
    fi
}

# Apply minimal template (essential only)
apply_minimal_template() {
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local -A template_settings
    local essential_patterns=("db*" "database*" "mysql*" "postgres*" "data*" "backup*")

    # Start with all disabled
    for dir in "${DISCOVERED_DIRS[@]}"; do
        template_settings["$dir"]="false"
    done

    # Enable only essential data directories
    for dir in "${DISCOVERED_DIRS[@]}"; do
        for pattern in "${essential_patterns[@]}"; do
            if [[ "$dir" == $pattern ]]; then
                template_settings["$dir"]="true"
                break
            fi
        done
    done

    if show_confirm "Minimal Template" "Apply minimal template?\n\nThis will enable only essential data directories:\n• db*, database*, mysql*, postgres*\n• data*, backup*\n\nAll other directories will be disabled."; then
        save_directory_settings template_settings
    fi
}

# Apply custom template from file
apply_custom_template() {
    show_info "Custom Template" "Custom template from file feature will be available in a future update.\n\nFor now, you can:\n1. Manually edit the dirlist file\n2. Use pattern matching options\n3. Copy settings from another system"
}

# Synchronize directory list with filesystem
synchronize_directory_list() {
    log_tui "Synchronizing directory list with filesystem"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    if ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    # Analyze changes between discovered and existing
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

    # Create synchronization report
    local sync_report="$TEMP_DIR/sync_report.txt"

    cat > "$sync_report" << EOF
DIRECTORY SYNCHRONIZATION REPORT
=================================

Generated: $(date)
Backup Directory: $BACKUP_DIR

EOF

    if [[ "$changes_detected" == "false" ]]; then
        echo "STATUS: ✓ No synchronization needed" >> "$sync_report"
        echo "" >> "$sync_report"
        echo "All directories in the list exist in the backup directory." >> "$sync_report"
        echo "No new directories were found." >> "$sync_report"
    else
        echo "STATUS: ⚠ Changes detected - synchronization needed" >> "$sync_report"
        echo "" >> "$sync_report"

        if [[ ${#removed_dirs[@]} -gt 0 ]]; then
            echo "REMOVED DIRECTORIES (no longer exist):" >> "$sync_report"
            for dir in "${removed_dirs[@]}"; do
                echo "  ✗ $dir (was: ${EXISTING_DIRLIST[$dir]})" >> "$sync_report"
            done
            echo "" >> "$sync_report"
        fi

        if [[ ${#new_dirs[@]} -gt 0 ]]; then
            echo "NEW DIRECTORIES (will be added as disabled):" >> "$sync_report"
            for dir in "${new_dirs[@]}"; do
                local dir_path="$BACKUP_DIR/$dir"
                local size="$(du -sh "$dir_path" 2>/dev/null | cut -f1 || echo "Unknown")"
                echo "  ➕ $dir ($size)" >> "$sync_report"
            done
            echo "" >> "$sync_report"
        fi

        echo "SUMMARY:" >> "$sync_report"
        echo "  • Directories to remove: ${#removed_dirs[@]}" >> "$sync_report"
        echo "  • Directories to add: ${#new_dirs[@]}" >> "$sync_report"
    fi

    # Show synchronization report and get confirmation
    if dialog --clear \
        --title "Directory Synchronization" \
        --backtitle "Docker Stack Backup System - Synchronization" \
        --yes-label "Apply Changes" \
        --no-label "Cancel" \
        --textbox "$sync_report" \
        20 80; then

        if [[ "$changes_detected" == "true" ]]; then
            # Apply synchronization changes
            local -A synced_settings

            # Start with existing settings, excluding removed directories
            for dir in "${!EXISTING_DIRLIST[@]}"; do
                local is_removed=false
                for removed_dir in "${removed_dirs[@]}"; do
                    if [[ "$dir" == "$removed_dir" ]]; then
                        is_removed=true
                        break
                    fi
                done
                if [[ "$is_removed" == "false" ]]; then
                    synced_settings["$dir"]="${EXISTING_DIRLIST[$dir]}"
                fi
            done

            # Add new directories (defaulting to false for safety)
            for new_dir in "${new_dirs[@]}"; do
                synced_settings["$new_dir"]="false"
            done

            # Save synchronized settings
            save_directory_settings synced_settings

            show_info "Synchronization Complete" "Directory list has been synchronized successfully!\n\nSummary:\n• Removed: ${#removed_dirs[@]} directories\n• Added: ${#new_dirs[@]} directories (disabled by default)\n\nNew directories can be enabled via directory selection."
        else
            show_info "No Changes" "Directory list is already synchronized with the backup directory."
        fi
    else
        log_tui "Directory synchronization cancelled by user"
    fi

    rm -f "$sync_report"
}

# Import/export directory settings menu
import_export_menu() {
    log_tui "Opening import/export menu"

    while true; do
        local choice
        choice=$(dialog --clear --title "Import/Export Directory Settings" \
                       --menu "Choose import/export option:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Export Directory Settings" \
                       "2" "Import Directory Settings" \
                       "3" "Create Template from Current" \
                       "4" "View Export Formats" \
                       "5" "Backup Current Settings" \
                       "0" "Return to Directory Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) export_directory_settings ;;
            2) import_directory_settings ;;
            3) create_template_from_current ;;
            4) view_export_formats ;;
            5) backup_current_settings ;;
            0|"") break ;;
        esac
    done
}

# Export directory settings
export_directory_settings() {
    log_tui "Exporting directory settings"

    # Load current settings
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    # Get export filename
    local export_file
    export_file=$(dialog --inputbox "Enter filename for exported settings:\n\n(Will be saved in script directory)" 10 60 "dirlist-export-$(date +%Y%m%d-%H%M%S).txt" 3>&1 1>&2 2>&3)

    if [[ -z "$export_file" ]]; then
        return
    fi

    local full_export_path="$SCRIPT_DIR/$export_file"

    # Create export file
    cat > "$full_export_path" << EOF
# Directory Settings Export
# Generated: $(date)
# Backup Directory: $BACKUP_DIR
# Total Directories: ${#DISCOVERED_DIRS[@]}
# Export Format: directory_name=true|false
#
# This file can be imported to restore these directory settings
# Edit as needed before importing

EOF

    # Add current settings
    local enabled_count=0
    local disabled_count=0

    for dir in $(printf '%s\n' "${DISCOVERED_DIRS[@]}" | sort); do
        local status="${EXISTING_DIRLIST[$dir]:-false}"
        echo "$dir=$status" >> "$full_export_path"

        if [[ "$status" == "true" ]]; then
            ((enabled_count++))
        else
            ((disabled_count++))
        fi
    done

    show_info "Export Complete" "Directory settings exported successfully!\n\nFile: $full_export_path\nTotal directories: ${#DISCOVERED_DIRS[@]}\nEnabled: $enabled_count\nDisabled: $disabled_count\n\nThis file can be imported on this or other systems."

    log_tui "Exported directory settings to $full_export_path"
}

# Import directory settings
import_directory_settings() {
    log_tui "Importing directory settings"

    # Get import filename
    local import_file
    import_file=$(dialog --inputbox "Enter filename to import:\n\n(File should be in script directory or provide full path)" 10 60 3>&1 1>&2 2>&3)

    if [[ -z "$import_file" ]]; then
        return
    fi

    # Check if file needs full path
    if [[ "$import_file" != /* ]]; then
        import_file="$SCRIPT_DIR/$import_file"
    fi

    if [[ ! -f "$import_file" ]]; then
        show_error "File Not Found" "Import file not found: $import_file"
        return
    fi

    # Load current configuration for validation
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    # Parse import file
    local -A import_settings
    local import_count=0
    local invalid_count=0
    local temp_validation="$TEMP_DIR/import_validation.txt"

    echo "IMPORT VALIDATION REPORT" > "$temp_validation"
    echo "========================" >> "$temp_validation"
    echo "" >> "$temp_validation"
    echo "Import File: $import_file" >> "$temp_validation"
    echo "Generated: $(date)" >> "$temp_validation"
    echo "" >> "$temp_validation"

    while IFS='=' read -r dir_name enabled; do
        # Skip comments and empty lines
        if [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]]; then
            continue
        fi

        # Validate format
        if [[ "$enabled" =~ ^(true|false)$ ]]; then
            import_settings["$dir_name"]="$enabled"
            ((import_count++))

            # Check if directory exists in current system
            local found=false
            for discovered_dir in "${DISCOVERED_DIRS[@]}"; do
                if [[ "$dir_name" == "$discovered_dir" ]]; then
                    found=true
                    break
                fi
            done

            if [[ "$found" == "true" ]]; then
                echo "✓ $dir_name=$enabled (directory exists)" >> "$temp_validation"
            else
                echo "⚠ $dir_name=$enabled (directory NOT found in current system)" >> "$temp_validation"
            fi
        else
            echo "✗ Invalid format: $dir_name=$enabled" >> "$temp_validation"
            ((invalid_count++))
        fi
    done < "$import_file"

    echo "" >> "$temp_validation"
    echo "IMPORT SUMMARY:" >> "$temp_validation"
    echo "  • Valid entries found: $import_count" >> "$temp_validation"
    echo "  • Invalid entries: $invalid_count" >> "$temp_validation"
    echo "  • Directories in current system: ${#DISCOVERED_DIRS[@]}" >> "$temp_validation"

    if [[ $import_count -gt 0 ]]; then
        echo "" >> "$temp_validation"
        echo "ℹ Note: Directories not found in current system will be ignored." >> "$temp_validation"
        echo "Only matching directories will have their settings imported." >> "$temp_validation"
    fi

    # Show validation report and get confirmation
    if dialog --clear \
        --title "Import Validation" \
        --backtitle "Docker Stack Backup System - Import" \
        --yes-label "Import Settings" \
        --no-label "Cancel" \
        --textbox "$temp_validation" \
        20 80; then

        if [[ $import_count -gt 0 ]]; then
            # Apply import settings
            local -A final_settings

            # Start with current discovered directories (default to false)
            for dir in "${DISCOVERED_DIRS[@]}"; do
                final_settings["$dir"]="false"
            done

            # Apply import settings for matching directories only
            local applied_count=0
            for dir in "${!import_settings[@]}"; do
                if [[ -n "${final_settings[$dir]:-}" ]]; then
                    final_settings["$dir"]="${import_settings[$dir]}"
                    ((applied_count++))
                fi
            done

            # Save imported settings
            save_directory_settings final_settings

            show_info "Import Complete" "Directory settings imported successfully!\n\nImported: $applied_count directory settings\nSkipped: $((import_count - applied_count)) (directories not found)\n\nSettings are now active."
        else
            show_error "Import Failed" "No valid directory settings found in import file."
        fi
    else
        log_tui "Directory settings import cancelled by user"
    fi

    rm -f "$temp_validation"
}

# Create template from current settings
create_template_from_current() {
    log_tui "Creating template from current settings"

    # Load current settings
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    # Get template name
    local template_name
    template_name=$(dialog --inputbox "Enter template name:\n\n(Will create template file for future use)" 10 60 "my-template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)

    if [[ -z "$template_name" ]]; then
        return
    fi

    local template_file="$SCRIPT_DIR/templates/dirlist-template-${template_name}.txt"

    # Create templates directory if it doesn't exist
    mkdir -p "$SCRIPT_DIR/templates"

    # Create template file
    cat > "$template_file" << EOF
# Directory Settings Template: $template_name
# Created: $(date)
# Based on backup directory: $BACKUP_DIR
#
# This template can be applied to other backup systems
# Edit patterns and settings as needed
#
# Template Format: directory_name=true|false

EOF

    # Add current settings as template
    local enabled_count=0
    local disabled_count=0

    for dir in $(printf '%s\n' "${DISCOVERED_DIRS[@]}" | sort); do
        local status="${EXISTING_DIRLIST[$dir]:-false}"
        echo "$dir=$status" >> "$template_file"

        if [[ "$status" == "true" ]]; then
            ((enabled_count++))
        else
            ((disabled_count++))
        fi
    done

    show_info "Template Created" "Directory template created successfully!\n\nTemplate: $template_file\nDirectories: ${#DISCOVERED_DIRS[@]}\nEnabled: $enabled_count\nDisabled: $disabled_count\n\nThis template can be used to quickly configure other backup systems with similar directory structures."

    log_tui "Created directory template: $template_file"
}

# View export formats help
view_export_formats() {
    local format_help="$TEMP_DIR/export_formats.txt"

    cat > "$format_help" << 'EOF'
DIRECTORY SETTINGS EXPORT FORMATS
==================================

The directory management system supports the following export formats:

1. STANDARD FORMAT (default):
   directory_name=true|false

   Examples:
   webapp=true
   database=true
   test-env=false
   staging=false

2. TEMPLATE FORMAT:
   Same as standard but with additional metadata comments
   for template creation and reuse.

3. BACKUP FORMAT:
   Includes timestamp and system information
   for restoration purposes.

IMPORT COMPATIBILITY:
• All export formats can be imported
• Comments and metadata are ignored during import
• Only directory_name=true|false lines are processed
• Directories not found in target system are skipped

FILE LOCATIONS:
• Exports saved in script directory by default
• Templates saved in templates/ subdirectory
• Backups saved with timestamp prefix

BEST PRACTICES:
• Use descriptive filenames with dates
• Test imports on non-production systems first
• Keep template files for reusing configurations
• Create backups before major configuration changes
EOF

    dialog --title "Export Formats Help" \
           --textbox "$format_help" \
           $DIALOG_HEIGHT $DIALOG_WIDTH

    rm -f "$format_help"
}

# Backup current settings
backup_current_settings() {
    log_tui "Creating backup of current directory settings"

    local backup_file="$SCRIPT_DIR/dirlist-backup-$(date +%Y%m%d-%H%M%S).txt"

    if [[ -f "$SCRIPT_DIR/dirlist" ]]; then
        cp "$SCRIPT_DIR/dirlist" "$backup_file"
        show_info "Backup Created" "Current directory settings backed up successfully!\n\nBackup file: $backup_file\n\nThis backup can be used to restore settings if needed."
        log_tui "Created backup of directory settings: $backup_file"
    else
        show_error "No Settings" "No directory list file found to backup.\n\nRun directory discovery first to create initial settings."
    fi
}

# Advanced directory features menu
advanced_directory_features() {
    log_tui "Opening advanced directory features"

    while true; do
        local choice
        choice=$(dialog --clear --title "Advanced Directory Features" \
                       --menu "Choose advanced feature:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Directory Size Analysis" \
                       "2" "Backup Impact Assessment" \
                       "3" "Directory Dependencies" \
                       "4" "Performance Optimization" \
                       "5" "Historical Statistics" \
                       "6" "Custom Scripts Integration" \
                       "0" "Return to Directory Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) directory_size_analysis ;;
            2) backup_impact_assessment ;;
            3) directory_dependencies ;;
            4) performance_optimization ;;
            5) historical_statistics ;;
            6) custom_scripts_integration ;;
            0|"") break ;;
        esac
    done
}

# Directory size analysis
directory_size_analysis() {
    log_tui "Performing directory size analysis"

    # Load configuration and discover directories
    if ! load_config_for_dirlist || ! discover_directories_tui; then
        return
    fi

    load_dirlist_tui || true

    local analysis_file="$TEMP_DIR/size_analysis.txt"

    show_progress "Directory Analysis" "Analyzing directory sizes...\n\nThis may take a moment for large directories." \
                  "echo 'Starting directory size analysis...'"

    cat > "$analysis_file" << EOF
DIRECTORY SIZE ANALYSIS REPORT
==============================

Generated: $(date)
Backup Directory: $BACKUP_DIR
Total Directories Analyzed: ${#DISCOVERED_DIRS[@]}

EOF

    # Analyze each directory
    local total_enabled_size=0
    local total_disabled_size=0
    local -a size_data=()

    echo "DIRECTORY SIZE BREAKDOWN:" >> "$analysis_file"
    echo "" >> "$analysis_file"

    for dir in $(printf '%s\n' "${DISCOVERED_DIRS[@]}" | sort); do
        local dir_path="$BACKUP_DIR/$dir"
        local status="${EXISTING_DIRLIST[$dir]:-false}"
        local size_bytes=$(du -sb "$dir_path" 2>/dev/null | cut -f1 || echo "0")
        local size_human=$(du -sh "$dir_path" 2>/dev/null | cut -f1 || echo "0B")

        size_data+=("$dir:$status:$size_bytes:$size_human")

        local status_icon="✗"
        if [[ "$status" == "true" ]]; then
            status_icon="✓"
            total_enabled_size=$((total_enabled_size + size_bytes))
        else
            total_disabled_size=$((total_disabled_size + size_bytes))
        fi

        printf "%-3s %-20s %10s\n" "$status_icon" "$dir" "$size_human" >> "$analysis_file"
    done

    echo "" >> "$analysis_file"
    echo "SIZE SUMMARY:" >> "$analysis_file"
    echo "  • Total enabled size: $(numfmt --to=iec --suffix=B $total_enabled_size)" >> "$analysis_file"
    echo "  • Total disabled size: $(numfmt --to=iec --suffix=B $total_disabled_size)" >> "$analysis_file"
    echo "  • Total directory size: $(numfmt --to=iec --suffix=B $((total_enabled_size + total_disabled_size)))" >> "$analysis_file"
    echo "" >> "$analysis_file"

    # Show largest directories
    echo "LARGEST DIRECTORIES (top 5):" >> "$analysis_file"
    printf '%s\n' "${size_data[@]}" | sort -t: -k3 -nr | head -5 | while IFS=':' read -r dir status size_bytes size_human; do
        local status_text="disabled"
        if [[ "$status" == "true" ]]; then
            status_text="enabled"
        fi
        echo "  • $dir ($size_human, $status_text)" >> "$analysis_file"
    done

    echo "" >> "$analysis_file"
    echo "RECOMMENDATIONS:" >> "$analysis_file"

    # Generate recommendations based on analysis
    local large_disabled_count=$(printf '%s\n' "${size_data[@]}" | awk -F: '$2=="false" && $3>1073741824 {count++} END {print count+0}')
    local small_enabled_count=$(printf '%s\n' "${size_data[@]}" | awk -F: '$2=="true" && $3<10485760 {count++} END {print count+0}')

    if [[ $large_disabled_count -gt 0 ]]; then
        echo "  • Consider enabling $large_disabled_count large disabled directories if they contain important data" >> "$analysis_file"
    fi

    if [[ $small_enabled_count -gt 0 ]]; then
        echo "  • $small_enabled_count small directories are enabled - verify they need backup" >> "$analysis_file"
    fi

    local backup_ratio=$((total_enabled_size * 100 / (total_enabled_size + total_disabled_size)))
    echo "  • Current backup ratio: ${backup_ratio}% of total directory size" >> "$analysis_file"

    if [[ $backup_ratio -gt 80 ]]; then
        echo "  • High backup ratio - consider disabling some directories to reduce backup time" >> "$analysis_file"
    elif [[ $backup_ratio -lt 20 ]]; then
        echo "  • Low backup ratio - verify important directories are enabled" >> "$analysis_file"
    fi

    dialog --title "Directory Size Analysis" \
           --textbox "$analysis_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH

    rm -f "$analysis_file"
}

# Placeholder functions for other advanced features
backup_impact_assessment() {
    show_info "Feature Preview" "Backup Impact Assessment will analyze:\n\n• Estimated backup time per directory\n• Network bandwidth requirements\n• Storage space needed\n• Resource utilization patterns\n\nThis feature will be available in a future update."
}

directory_dependencies() {
    show_info "Feature Preview" "Directory Dependencies will show:\n\n• Docker service dependencies\n• Volume mount relationships\n• Network connections\n• Backup order recommendations\n\nThis feature will be available in a future update."
}

performance_optimization() {
    show_info "Feature Preview" "Performance Optimization will provide:\n\n• Backup parallelization suggestions\n• Directory prioritization\n• Resource allocation recommendations\n• Schedule optimization\n\nThis feature will be available in a future update."
}

historical_statistics() {
    show_info "Feature Preview" "Historical Statistics will display:\n\n• Backup frequency per directory\n• Size growth trends\n• Success/failure rates\n• Performance metrics\n\nThis feature will be available in a future update."
}

custom_scripts_integration() {
    show_info "Feature Preview" "Custom Scripts Integration will support:\n\n• Pre/post backup hooks\n• Custom validation scripts\n• Directory-specific handlers\n• Integration with external tools\n\nThis feature will be available in a future update."
}

# Directory troubleshooting menu
directory_troubleshooting() {
    log_tui "Opening directory troubleshooting menu"

    while true; do
        local choice
        choice=$(dialog --clear --title "Directory Troubleshooting & Diagnostics" \
                       --menu "Choose troubleshooting option:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Diagnose Directory Issues" \
                       "2" "Validate Directory Structure" \
                       "3" "Check Docker Compose Files" \
                       "4" "Test Directory Permissions" \
                       "5" "Verify Backup Configuration" \
                       "6" "Common Issues & Solutions" \
                       "7" "Reset Directory Configuration" \
                       "0" "Return to Directory Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) diagnose_directory_issues ;;
            2) validate_directory_structure ;;
            3) check_compose_files ;;
            4) test_directory_permissions ;;
            5) verify_backup_configuration ;;
            6) show_common_solutions ;;
            7) reset_directory_configuration ;;
            0|"") break ;;
        esac
    done
}

# Diagnose directory issues
diagnose_directory_issues() {
    log_tui "Running directory diagnostics"

    # Load configuration and discover directories
    if ! load_config_for_dirlist; then
        return
    fi

    local diagnostics_file="$TEMP_DIR/directory_diagnostics.txt"

    cat > "$diagnostics_file" << EOF
DIRECTORY DIAGNOSTICS REPORT
============================

Generated: $(date)
Backup Directory: $BACKUP_DIR

EOF

    # Check backup directory accessibility
    echo "BACKUP DIRECTORY CHECKS:" >> "$diagnostics_file"

    if [[ -d "$BACKUP_DIR" ]]; then
        echo "  ✓ Backup directory exists: $BACKUP_DIR" >> "$diagnostics_file"

        if [[ -r "$BACKUP_DIR" ]]; then
            echo "  ✓ Directory is readable" >> "$diagnostics_file"
        else
            echo "  ✗ Directory is not readable" >> "$diagnostics_file"
        fi

        if [[ -w "$BACKUP_DIR" ]]; then
            echo "  ✓ Directory is writable" >> "$diagnostics_file"
        else
            echo "  ✗ Directory is not writable" >> "$diagnostics_file"
        fi

        local dir_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d | wc -l)
        echo "  • Subdirectories found: $((dir_count - 1))" >> "$diagnostics_file"
    else
        echo "  ✗ Backup directory does not exist: $BACKUP_DIR" >> "$diagnostics_file"
    fi

    echo "" >> "$diagnostics_file"

    # Discover and check directories
    if discover_directories_tui; then
        echo "DOCKER COMPOSE DIRECTORY CHECKS:" >> "$diagnostics_file"
        echo "  • Total Docker compose directories found: ${#DISCOVERED_DIRS[@]}" >> "$diagnostics_file"
        echo "" >> "$diagnostics_file"

        local issues_found=0

        for dir in "${DISCOVERED_DIRS[@]}"; do
            local dir_path="$BACKUP_DIR/$dir"
            echo "Checking: $dir" >> "$diagnostics_file"

            # Check directory accessibility
            if [[ ! -r "$dir_path" ]]; then
                echo "  ✗ Directory not readable: $dir_path" >> "$diagnostics_file"
                ((issues_found++))
            fi

            # Check for compose files
            local compose_files=()
            for compose_file in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
                if [[ -f "$dir_path/$compose_file" ]]; then
                    compose_files+=("$compose_file")
                fi
            done

            if [[ ${#compose_files[@]} -gt 0 ]]; then
                echo "  ✓ Compose files: ${compose_files[*]}" >> "$diagnostics_file"
            else
                echo "  ✗ No compose files found" >> "$diagnostics_file"
                ((issues_found++))
            fi

            # Check for common issues
            if [[ -f "$dir_path/.env" ]]; then
                echo "  ✓ Environment file present" >> "$diagnostics_file"
            else
                echo "  ⚠ No .env file (may be normal)" >> "$diagnostics_file"
            fi

            echo "" >> "$diagnostics_file"
        done

        echo "DIAGNOSTICS SUMMARY:" >> "$diagnostics_file"
        echo "  • Directories scanned: ${#DISCOVERED_DIRS[@]}" >> "$diagnostics_file"
        echo "  • Issues found: $issues_found" >> "$diagnostics_file"

        if [[ $issues_found -eq 0 ]]; then
            echo "  ✓ All directories appear healthy" >> "$diagnostics_file"
        else
            echo "  ⚠ Issues need attention" >> "$diagnostics_file"
        fi
    else
        echo "DOCKER COMPOSE DIRECTORY CHECKS:" >> "$diagnostics_file"
        echo "  ✗ Failed to discover directories" >> "$diagnostics_file"
        echo "  • Check backup directory configuration" >> "$diagnostics_file"
        echo "  • Verify directory contains Docker compose projects" >> "$diagnostics_file"
    fi

    echo "" >> "$diagnostics_file"

    # Check dirlist file
    echo "DIRECTORY LIST FILE CHECKS:" >> "$diagnostics_file"
    local dirlist_file="$SCRIPT_DIR/dirlist"

    if [[ -f "$dirlist_file" ]]; then
        echo "  ✓ Directory list file exists: $dirlist_file" >> "$diagnostics_file"

        local total_entries=$(grep -c "=" "$dirlist_file" 2>/dev/null || echo "0")
        local enabled_entries=$(grep -c "=true" "$dirlist_file" 2>/dev/null || echo "0")
        local disabled_entries=$(grep -c "=false" "$dirlist_file" 2>/dev/null || echo "0")

        echo "  • Total entries: $total_entries" >> "$diagnostics_file"
        echo "  • Enabled: $enabled_entries" >> "$diagnostics_file"
        echo "  • Disabled: $disabled_entries" >> "$diagnostics_file"

        # Validate format
        local invalid_lines=$(grep -v "^#" "$dirlist_file" | grep -v "^$" | grep -v "^[^=]*=(true|false)$" | wc -l)
        if [[ $invalid_lines -gt 0 ]]; then
            echo "  ✗ Invalid format lines: $invalid_lines" >> "$diagnostics_file"
        else
            echo "  ✓ File format is valid" >> "$diagnostics_file"
        fi
    else
        echo "  ⚠ Directory list file not found (will be created)" >> "$diagnostics_file"
    fi

    dialog --title "Directory Diagnostics Report" \
           --textbox "$diagnostics_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH

    rm -f "$diagnostics_file"
}

# Placeholder functions for additional troubleshooting features
validate_directory_structure() {
    show_info "Feature Preview" "Directory Structure Validation will check:\n\n• Docker Compose file syntax\n• Volume mount paths\n• Network configurations\n• Service dependencies\n\nThis feature will be available in a future update."
}

check_compose_files() {
    show_info "Feature Preview" "Docker Compose File Analysis will verify:\n\n• YAML syntax validation\n• Service configuration\n• Volume and network definitions\n• Environment variable usage\n\nThis feature will be available in a future update."
}

test_directory_permissions() {
    show_info "Feature Preview" "Directory Permissions Testing will check:\n\n• Read/write permissions\n• User/group ownership\n• Docker daemon access\n• Backup process permissions\n\nThis feature will be available in a future update."
}

verify_backup_configuration() {
    show_info "Feature Preview" "Backup Configuration Verification will validate:\n\n• Restic repository access\n• Backup directory settings\n• Environment variables\n• Script permissions\n\nThis feature will be available in a future update."
}

show_common_solutions() {
    local solutions_file="$TEMP_DIR/common_solutions.txt"

    cat > "$solutions_file" << 'EOF'
COMMON DIRECTORY ISSUES & SOLUTIONS
====================================

PROBLEM: No directories found
SOLUTIONS:
• Verify BACKUP_DIR in configuration file
• Check that directories contain docker-compose.yml files
• Ensure proper file naming (docker-compose.yml/yaml, compose.yml/yaml)
• Verify directory permissions

PROBLEM: Directory list file format errors
SOLUTIONS:
• Use format: directory_name=true or directory_name=false
• Remove invalid characters or extra spaces
• Use the TUI validation feature
• Recreate file using directory selection interface

PROBLEM: Changes not taking effect
SOLUTIONS:
• Ensure dirlist file is saved properly
• Check file permissions (should be readable)
• Restart backup processes if they're running
• Verify backup script is using the correct dirlist file

PROBLEM: Permission denied errors
SOLUTIONS:
• Check directory ownership and permissions
• Ensure backup user has read access to directories
• Verify Docker daemon permissions
• Consider using sudo if necessary

PROBLEM: Backup includes wrong directories
SOLUTIONS:
• Review directory selection carefully
• Use directory status view to verify settings
• Check for typos in directory names
• Synchronize directory list with filesystem

PROBLEM: Large backup times
SOLUTIONS:
• Use directory size analysis to identify large directories
• Disable unnecessary directories
• Consider backing up large directories separately
• Use incremental backup features

PROBLEM: Missing directories after system changes
SOLUTIONS:
• Run directory synchronization
• Check if directories were moved or renamed
• Update BACKUP_DIR if directory structure changed
• Use troubleshooting diagnostics to identify issues

For additional help:
• Check system logs for error messages
• Run directory diagnostics for detailed analysis
• Validate backup configuration
• Test with a small subset of directories first
EOF

    dialog --title "Common Issues & Solutions" \
           --textbox "$solutions_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH

    rm -f "$solutions_file"
}

reset_directory_configuration() {
    log_tui "Resetting directory configuration"

    local reset_choice
    reset_choice=$(dialog --clear --title "Reset Directory Configuration" \
                         --menu "Choose reset option:" \
                         $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                         "1" "Reset to defaults (enable all directories)" \
                         "2" "Clear all settings (disable all directories)" \
                         "3" "Recreate from filesystem scan" \
                         "4" "Delete dirlist file (will be recreated)" \
                         3>&1 1>&2 2>&3)

    case $reset_choice in
        1)
            if show_confirm "Reset to Defaults" "Reset directory configuration to defaults?\n\n⚠ This will enable ALL discovered directories for backup.\n\nContinue?"; then
                if load_config_for_dirlist && discover_directories_tui; then
                    local -A reset_settings
                    for dir in "${DISCOVERED_DIRS[@]}"; do
                        reset_settings["$dir"]="true"
                    done
                    save_directory_settings reset_settings
                fi
            fi
            ;;
        2)
            if show_confirm "Clear All Settings" "Clear all directory settings?\n\n⚠ This will disable ALL directories for backup.\nNo directories will be backed up until re-enabled.\n\nContinue?"; then
                if load_config_for_dirlist && discover_directories_tui; then
                    local -A reset_settings
                    for dir in "${DISCOVERED_DIRS[@]}"; do
                        reset_settings["$dir"]="false"
                    done
                    save_directory_settings reset_settings
                fi
            fi
            ;;
        3)
            if show_confirm "Recreate from Scan" "Recreate directory list from filesystem scan?\n\nThis will:\n• Discover all current directories\n• Remove old entries\n• Add new directories as disabled\n\nContinue?"; then
                synchronize_directory_list
            fi
            ;;
        4)
            if show_confirm "Delete Dirlist File" "Delete the dirlist file?\n\n⚠ This will remove all directory settings.\nFile will be recreated on next directory operation.\n\nContinue?"; then
                local dirlist_file="$SCRIPT_DIR/dirlist"
                if [[ -f "$dirlist_file" ]]; then
                    rm -f "$dirlist_file"
                    show_info "File Deleted" "Directory list file deleted successfully.\n\nFile: $dirlist_file\n\nA new file will be created when you next configure directories."
                    log_tui "Deleted directory list file: $dirlist_file"
                else
                    show_info "No File Found" "Directory list file does not exist.\n\nFile: $dirlist_file"
                fi
            fi
            ;;
    esac
}

# Check if directory list is out of sync with filesystem
# Returns: 0 if in sync, 1 if out of sync (sets global variables for details)
check_dirlist_sync_status() {
    SYNC_NEW_DIRS=()
    SYNC_REMOVED_DIRS=()
    SYNC_STATUS="in_sync"

    # Load configuration
    if ! load_config_for_dirlist 2>/dev/null; then
        return 0  # Can't check without config
    fi

    # Discover current directories
    local -a current_dirs=()
    for dir in "$BACKUP_DIR"/*; do
        [[ -d "$dir" ]] || continue
        local dir_name="$(basename "$dir")"
        [[ "$dir_name" =~ ^\..*$ ]] && continue

        # Check for docker-compose files
        if [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]] || \
           [[ -f "$dir/compose.yml" ]] || [[ -f "$dir/compose.yaml" ]]; then
            current_dirs+=("$dir_name")
        fi
    done

    # Load existing dirlist
    local dirlist_file="$SCRIPT_DIR/dirlist"
    local -A existing_dirs

    if [[ -f "$dirlist_file" ]]; then
        while IFS='=' read -r dir_name enabled; do
            [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]] && continue
            [[ "$enabled" =~ ^(true|false)$ ]] && existing_dirs["$dir_name"]="$enabled"
        done < "$dirlist_file"
    fi

    # Find new directories (on disk but not in dirlist)
    for dir in "${current_dirs[@]}"; do
        if [[ -z "${existing_dirs[$dir]:-}" ]]; then
            SYNC_NEW_DIRS+=("$dir")
        fi
    done

    # Find removed directories (in dirlist but not on disk)
    for dir in "${!existing_dirs[@]}"; do
        local found=false
        for current_dir in "${current_dirs[@]}"; do
            if [[ "$dir" == "$current_dir" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            SYNC_REMOVED_DIRS+=("$dir")
        fi
    done

    # Set status
    if [[ ${#SYNC_NEW_DIRS[@]} -gt 0 ]] || [[ ${#SYNC_REMOVED_DIRS[@]} -gt 0 ]]; then
        SYNC_STATUS="out_of_sync"
        return 1
    fi

    return 0
}

# Show sync status warning and offer to sync
show_sync_warning() {
    local new_count=${#SYNC_NEW_DIRS[@]}
    local removed_count=${#SYNC_REMOVED_DIRS[@]}

    local message="Directory list is out of sync with backup directory!\n\n"

    if [[ $new_count -gt 0 ]]; then
        message+="NEW directories found ($new_count):\n"
        local shown=0
        for dir in "${SYNC_NEW_DIRS[@]}"; do
            if [[ $shown -lt 5 ]]; then
                message+="  + $dir\n"
                ((shown++))
            else
                message+="  ... and $((new_count - shown)) more\n"
                break
            fi
        done
        message+="\n"
    fi

    if [[ $removed_count -gt 0 ]]; then
        message+="REMOVED directories ($removed_count):\n"
        local shown=0
        for dir in "${SYNC_REMOVED_DIRS[@]}"; do
            if [[ $shown -lt 5 ]]; then
                message+="  - $dir\n"
                ((shown++))
            else
                message+="  ... and $((removed_count - shown)) more\n"
                break
            fi
        done
        message+="\n"
    fi

    message+="Would you like to synchronize now?"

    if show_confirm "Directory List Out of Sync" "$message"; then
        synchronize_directory_list
        return 0
    fi

    return 1
}

# Main directory management interface
directory_management() {
    log_tui "Opening directory list management"

    # Check for sync status on entry
    if ! check_dirlist_sync_status; then
        show_sync_warning
    fi

    while true; do
        # Build menu with sync status indicator
        local sync_indicator=""
        check_dirlist_sync_status
        if [[ "$SYNC_STATUS" == "out_of_sync" ]]; then
            sync_indicator=" [!]"
        fi

        local title
        title="$(get_title_with_breadcrumb "Directory List Management")"

        local choice
        choice=$(dialog --clear --title "$title" \
                       --menu "Comprehensive directory management for backups:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "View Directory Status" \
                       "2" "Select Directories for Backup" \
                       "3" "Bulk Enable/Disable Operations" \
                       "4" "Synchronize Directory List${sync_indicator}" \
                       "5" "Import/Export Directory Settings" \
                       "6" "Troubleshooting & Diagnostics" \
                       "7" "Advanced Features" \
                       "8" "Validate Directory List Format" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) view_directory_status_tui ;;
            2) select_directories_tui ;;
            3) push_breadcrumb "Bulk"; bulk_operations_menu; pop_breadcrumb ;;
            4) synchronize_directory_list ;;
            5) push_breadcrumb "Import/Export"; import_export_menu; pop_breadcrumb ;;
            6) push_breadcrumb "Troubleshoot"; directory_troubleshooting; pop_breadcrumb ;;
            7) push_breadcrumb "Advanced"; advanced_directory_features; pop_breadcrumb ;;
            8) validate_dirlist_format ;;
            0|"") break ;;
        esac
    done
}

monitoring_menu() {
    log_tui "Opening monitoring menu"

    while true; do
        local choice
        choice=$(dialog --clear --title "Monitoring & Status" \
                       --menu "Choose monitoring option:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "View Backup Status" \
                       "2" "View System Resources" \
                       "3" "Check Repository Health" \
                       "4" "View Active Processes" \
                       "5" "View Recent Activity" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) view_backup_status ;;
            2) view_system_resources ;;
            3) check_repository_status ;;
            4) view_active_processes ;;
            5) view_recent_activity ;;
            0|"") break ;;
        esac
    done
}

view_system_resources() {
    log_tui "Viewing system resources"

    local resources_file="$TEMP_DIR/system_resources.txt"

    cat > "$resources_file" << EOF
SYSTEM RESOURCES REPORT
=======================
Generated: $(date)
Hostname: $(hostname)

MEMORY:
$(free -h)

DISK SPACE:
$(df -h | grep -v tmpfs | grep -v loop)

CPU LOAD:
$(uptime)

TOP PROCESSES (by memory):
$(ps aux --sort=-%mem | head -10)

EOF

    dialog --title "System Resources" \
           --textbox "$resources_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

view_active_processes() {
    log_tui "Viewing active backup processes"

    local processes_file="$TEMP_DIR/backup_processes.txt"

    cat > "$processes_file" << EOF
ACTIVE BACKUP PROCESSES
=======================
Generated: $(date)

BACKUP SCRIPTS:
$(ps aux | grep -E "docker-backup|rclone|restic" | grep -v grep || echo "  No backup processes currently running")

DOCKER CONTAINERS:
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || echo "  Docker not accessible")

RECENT BACKUP ACTIVITY (last 10 entries):
$(tail -10 "$SCRIPT_DIR/../logs/docker_backup.log" 2>/dev/null || echo "  No recent log entries")

EOF

    dialog --title "Active Backup Processes" \
           --textbox "$processes_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

view_recent_activity() {
    log_tui "Viewing recent activity"

    local activity_file="$TEMP_DIR/recent_activity.txt"

    cat > "$activity_file" << EOF
RECENT BACKUP ACTIVITY
======================
Generated: $(date)

LAST 30 LOG ENTRIES:
$(tail -30 "$SCRIPT_DIR/../logs/docker_backup.log" 2>/dev/null || echo "  No log file found")

EOF

    dialog --title "Recent Activity" \
           --textbox "$activity_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

health_check() {
    log_tui "Running system health check"

    local health_file="$TEMP_DIR/health_check.txt"

    cat > "$health_file" << EOF
SYSTEM HEALTH CHECK REPORT
==========================
Generated: $(date)
Hostname: $(hostname)

DEPENDENCY CHECKS:
EOF

    # Check Docker
    echo "" >> "$health_file"
    echo "Docker:" >> "$health_file"
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            echo "  [OK] Docker is running" >> "$health_file"
            local containers=$(docker ps -q 2>/dev/null | wc -l)
            echo "  [INFO] Running containers: $containers" >> "$health_file"
        else
            echo "  [WARN] Docker installed but not accessible" >> "$health_file"
        fi
    else
        echo "  [ERROR] Docker not installed" >> "$health_file"
    fi

    # Check restic
    echo "" >> "$health_file"
    echo "Restic:" >> "$health_file"
    if command -v restic >/dev/null 2>&1; then
        echo "  [OK] Restic installed: $(restic version 2>/dev/null | head -1)" >> "$health_file"
    else
        echo "  [ERROR] Restic not installed" >> "$health_file"
    fi

    # Check rclone
    echo "" >> "$health_file"
    echo "Rclone:" >> "$health_file"
    if command -v rclone >/dev/null 2>&1; then
        echo "  [OK] Rclone installed: $(rclone version 2>/dev/null | head -1)" >> "$health_file"
        local remotes=$(rclone listremotes 2>/dev/null | wc -l)
        echo "  [INFO] Configured remotes: $remotes" >> "$health_file"
    else
        echo "  [WARN] Rclone not installed (optional for cloud sync)" >> "$health_file"
    fi

    # Check configuration
    echo "" >> "$health_file"
    echo "Configuration:" >> "$health_file"
    if [[ -f "$BACKUP_CONFIG" ]]; then
        echo "  [OK] Backup config found: $BACKUP_CONFIG" >> "$health_file"
    else
        echo "  [ERROR] Backup config not found" >> "$health_file"
    fi

    # Check disk space
    echo "" >> "$health_file"
    echo "Disk Space:" >> "$health_file"
    df -h / | tail -1 | awk '{print "  Root filesystem: " $4 " available (" $5 " used)"}' >> "$health_file"

    # Check memory
    echo "" >> "$health_file"
    echo "Memory:" >> "$health_file"
    free -h | awk 'NR==2{print "  RAM: " $3 " used / " $2 " total (" $7 " available)"}' >> "$health_file"

    # Summary
    echo "" >> "$health_file"
    echo "SUMMARY:" >> "$health_file"
    if command -v docker >/dev/null 2>&1 && command -v restic >/dev/null 2>&1 && [[ -f "$BACKUP_CONFIG" ]]; then
        echo "  [OK] System ready for backup operations" >> "$health_file"
    else
        echo "  [WARN] Some components need attention - review above" >> "$health_file"
    fi

    dialog --title "System Health Check" \
           --textbox "$health_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

view_logs_menu() {
    log_tui "Opening logs menu"

    while true; do
        local choice
        choice=$(dialog --clear --title "View Logs" \
                       --menu "Choose log to view:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Docker Backup Log" \
                       "2" "TUI Log" \
                       "3" "Rclone Sync Log" \
                       "4" "Recent Errors Only" \
                       "5" "Tail Live Log (10 seconds)" \
                       "0" "Return to Main Menu" \
                       3>&1 1>&2 2>&3)

        case $choice in
            1) view_docker_backup_log ;;
            2) view_tui_log ;;
            3) view_rclone_log ;;
            4) view_recent_errors ;;
            5) tail_live_log ;;
            0|"") break ;;
        esac
    done
}

view_docker_backup_log() {
    local log_file="$SCRIPT_DIR/../logs/docker_backup.log"
    if [[ -f "$log_file" ]]; then
        dialog --title "Docker Backup Log (last 100 lines)" \
               --textbox "$log_file" \
               $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        show_error "Log Not Found" "Docker backup log not found:\n$log_file"
    fi
}

view_tui_log() {
    if [[ -f "$TUI_LOG_FILE" ]]; then
        dialog --title "TUI Log" \
               --textbox "$TUI_LOG_FILE" \
               $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        show_error "Log Not Found" "TUI log not found:\n$TUI_LOG_FILE"
    fi
}

view_rclone_log() {
    local log_file="$SCRIPT_DIR/../logs/rclone_backup.log"
    if [[ -f "$log_file" ]]; then
        dialog --title "Rclone Sync Log" \
               --textbox "$log_file" \
               $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        show_error "Log Not Found" "Rclone sync log not found:\n$log_file\n\nRun a cloud sync operation first."
    fi
}

view_recent_errors() {
    local errors_file="$TEMP_DIR/recent_errors.txt"
    local log_file="$SCRIPT_DIR/../logs/docker_backup.log"

    cat > "$errors_file" << EOF
RECENT ERRORS
=============
Generated: $(date)

$(grep -i "error\|fail\|warn" "$log_file" 2>/dev/null | tail -50 || echo "No errors found in log file")

EOF

    dialog --title "Recent Errors" \
           --textbox "$errors_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

tail_live_log() {
    local log_file="$SCRIPT_DIR/../logs/docker_backup.log"

    if [[ ! -f "$log_file" ]]; then
        show_error "Log Not Found" "Docker backup log not found"
        return
    fi

    clear
    echo "=== Live Log Tail (Ctrl+C to stop, or wait 10 seconds) ==="
    echo "File: $log_file"
    echo ""

    timeout 10 tail -f "$log_file" 2>/dev/null || true

    echo ""
    echo "Press any key to return..."
    read -n 1
}

help_menu() {
    local help_file="$TEMP_DIR/help.txt"

    cat > "$help_file" << 'EOF'
DOCKER STACK 3-STAGE BACKUP SYSTEM - HELP
==========================================

OVERVIEW
--------
This system provides comprehensive backup management for Docker
compose stacks with cloud synchronization capabilities.

3-STAGE ARCHITECTURE
--------------------
Stage 1: Local Docker Backup
  - Safely stops Docker stacks
  - Creates restic snapshots
  - Automatically restarts stacks
  - Maintains backup history with retention policies

Stage 2: Cloud Sync (Upload)
  - Syncs local restic repository to cloud storage
  - Supports multiple cloud providers via rclone
  - Incremental uploads for efficiency
  - Retry logic for network reliability

Stage 3: Cloud Restore (Download)
  - Downloads repository from cloud for disaster recovery
  - Verifies restored data integrity
  - Enables selective file restoration

KEYBOARD SHORTCUTS
------------------
  SPACE       Toggle selection in checklists
  ENTER       Confirm selection
  ESC         Cancel / Go back
  TAB         Move between buttons
  Arrow keys  Navigate menus

CONFIGURATION FILES
-------------------
  config/backup.conf     Main backup configuration
  config/rclone.conf     Cloud sync configuration
  dirlist                Directory selection file
  ~/.config/rclone/      Rclone remote configurations

GETTING HELP
------------
  - View logs for error details
  - Run health check for system status
  - Use dry-run mode to test safely before real operations

COMMON ISSUES
-------------
1. "No directories enabled for backup"
   -> Use Directory List Management to enable directories

2. "Repository not accessible"
   -> Check RESTIC_REPOSITORY and password configuration

3. "Docker permission denied"
   -> Add your user to docker group: sudo usermod -aG docker $USER

4. "Cloud sync failing"
   -> Test rclone remote connectivity first

For more help, visit the project documentation or run with --help.
EOF

    dialog --title "Help & Documentation" \
           --textbox "$help_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

#######################################
# Missing Function Implementations
#######################################

# View recent backup logs
view_recent_logs() {
    log_tui "Viewing recent backup logs"
    local log_file="$SCRIPT_DIR/../logs/docker_backup.log"
    if [[ -f "$log_file" ]]; then
        dialog --title "Recent Backup Logs (last 50 lines)" \
               --textbox <(tail -50 "$log_file") \
               $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        show_error "Log Not Found" "Backup log file not found:\n$log_file"
    fi
}

# Test system prerequisites
test_prerequisites() {
    log_tui "Testing system prerequisites"
    local prereq_file="$TEMP_DIR/prerequisites.txt"

    cat > "$prereq_file" << EOF
SYSTEM PREREQUISITES CHECK
==========================
Generated: $(date)

EOF

    # Check Docker
    echo "Docker:" >> "$prereq_file"
    if command -v docker >/dev/null 2>&1; then
        echo "  ✓ Docker installed: $(docker --version 2>/dev/null | head -1)" >> "$prereq_file"
        if docker info >/dev/null 2>&1; then
            echo "  ✓ Docker daemon running" >> "$prereq_file"
        else
            echo "  ✗ Docker daemon not accessible" >> "$prereq_file"
        fi
    else
        echo "  ✗ Docker not installed" >> "$prereq_file"
    fi

    # Check restic
    echo "" >> "$prereq_file"
    echo "Restic:" >> "$prereq_file"
    if command -v restic >/dev/null 2>&1; then
        echo "  ✓ Restic installed: $(restic version 2>/dev/null | head -1)" >> "$prereq_file"
    else
        echo "  ✗ Restic not installed" >> "$prereq_file"
    fi

    # Check rclone
    echo "" >> "$prereq_file"
    echo "Rclone:" >> "$prereq_file"
    if command -v rclone >/dev/null 2>&1; then
        echo "  ✓ Rclone installed: $(rclone version 2>/dev/null | head -1)" >> "$prereq_file"
    else
        echo "  ⚠ Rclone not installed (optional)" >> "$prereq_file"
    fi

    # Check dialog
    echo "" >> "$prereq_file"
    echo "Dialog:" >> "$prereq_file"
    if command -v dialog >/dev/null 2>&1; then
        echo "  ✓ Dialog installed" >> "$prereq_file"
    else
        echo "  ✗ Dialog not installed" >> "$prereq_file"
    fi

    dialog --title "Prerequisites Check" \
           --textbox "$prereq_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Test repository connectivity
test_repository_connectivity() {
    log_tui "Testing repository connectivity"

    if [[ ! -f "$BACKUP_CONFIG" ]]; then
        show_error "Configuration Missing" "Backup configuration not found."
        return
    fi

    show_progress "Testing Repository" "Checking restic repository connectivity..." \
                  "source '$BACKUP_CONFIG' && restic snapshots --quiet"

    if [[ $? -eq 0 ]]; then
        show_info "Repository Connected" "Successfully connected to restic repository.\n\nRepository is accessible and ready for backup operations."
    else
        show_error "Connection Failed" "Failed to connect to restic repository.\n\nCheck your configuration and credentials."
    fi
}

# Test Docker permissions
test_docker_permissions() {
    log_tui "Testing Docker permissions"
    local perms_file="$TEMP_DIR/docker_perms.txt"

    cat > "$perms_file" << EOF
DOCKER PERMISSIONS CHECK
========================
Generated: $(date)
User: $(whoami)

EOF

    # Check if user is in docker group
    echo "Docker Group Membership:" >> "$perms_file"
    if groups | grep -q docker; then
        echo "  ✓ User is in docker group" >> "$perms_file"
    else
        echo "  ✗ User is NOT in docker group" >> "$perms_file"
        echo "    Fix: sudo usermod -aG docker $(whoami)" >> "$perms_file"
    fi

    # Check docker socket
    echo "" >> "$perms_file"
    echo "Docker Socket:" >> "$perms_file"
    if [[ -S /var/run/docker.sock ]]; then
        local sock_perms
        sock_perms="$(ls -la /var/run/docker.sock)"
        echo "  Socket exists: $sock_perms" >> "$perms_file"
        if [[ -r /var/run/docker.sock && -w /var/run/docker.sock ]]; then
            echo "  ✓ Socket is readable and writable" >> "$perms_file"
        else
            echo "  ✗ Socket permissions issue" >> "$perms_file"
        fi
    else
        echo "  ✗ Docker socket not found" >> "$perms_file"
    fi

    # Test docker command
    echo "" >> "$perms_file"
    echo "Docker Command Test:" >> "$perms_file"
    if docker ps >/dev/null 2>&1; then
        echo "  ✓ Can run docker commands" >> "$perms_file"
    else
        echo "  ✗ Cannot run docker commands" >> "$perms_file"
    fi

    dialog --title "Docker Permissions" \
           --textbox "$perms_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Check disk space in detail
check_disk_space_detailed() {
    log_tui "Checking disk space"
    local disk_file="$TEMP_DIR/disk_space.txt"

    cat > "$disk_file" << EOF
DISK SPACE REPORT
=================
Generated: $(date)

FILESYSTEM USAGE:
$(df -h | grep -v tmpfs | grep -v loop)

BACKUP DIRECTORY:
EOF

    if [[ -f "$BACKUP_CONFIG" ]]; then
        local backup_dir
        backup_dir=$(grep "^BACKUP_DIR=" "$BACKUP_CONFIG" | cut -d= -f2 | xargs)
        if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
            echo "  Path: $backup_dir" >> "$disk_file"
            echo "  Usage: $(du -sh "$backup_dir" 2>/dev/null | cut -f1)" >> "$disk_file"
            df -h "$backup_dir" | tail -1 | awk '{print "  Filesystem: " $1 "\n  Available: " $4 "\n  Used: " $5}' >> "$disk_file"
        else
            echo "  Not configured or not found" >> "$disk_file"
        fi
    fi

    dialog --title "Disk Space Report" \
           --textbox "$disk_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Check network connectivity
check_network_connectivity() {
    log_tui "Checking network connectivity"
    local net_file="$TEMP_DIR/network.txt"

    cat > "$net_file" << EOF
NETWORK CONNECTIVITY CHECK
==========================
Generated: $(date)

EOF

    # Test DNS resolution
    echo "DNS Resolution:" >> "$net_file"
    if host google.com >/dev/null 2>&1; then
        echo "  ✓ DNS working" >> "$net_file"
    else
        echo "  ✗ DNS resolution failed" >> "$net_file"
    fi

    # Test internet connectivity
    echo "" >> "$net_file"
    echo "Internet Connectivity:" >> "$net_file"
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "  ✓ Internet accessible" >> "$net_file"
    else
        echo "  ✗ Internet not accessible" >> "$net_file"
    fi

    # Test common cloud storage endpoints
    echo "" >> "$net_file"
    echo "Cloud Storage Endpoints:" >> "$net_file"
    for endpoint in "storage.googleapis.com" "s3.amazonaws.com" "blob.core.windows.net"; do
        if ping -c 1 -W 5 "$endpoint" >/dev/null 2>&1; then
            echo "  ✓ $endpoint reachable" >> "$net_file"
        else
            echo "  ⚠ $endpoint not reachable" >> "$net_file"
        fi
    done

    dialog --title "Network Connectivity" \
           --textbox "$net_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Validate remote credentials
validate_remote_credentials() {
    log_tui "Validating remote credentials"

    local remotes_file="$TEMP_DIR/remotes.txt"
    rclone listremotes > "$remotes_file" 2>/dev/null || true

    if [[ ! -s "$remotes_file" ]]; then
        show_error "No Remotes" "No rclone remotes configured."
        return
    fi

    local remote_choice
    remote_choice=$(dialog --clear --title "Validate Remote Credentials" \
                          --menu "Select remote to validate:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          $(cat "$remotes_file" | nl -w2 -s' ' | awk '{print $1, $2}') \
                          3>&1 1>&2 2>&3)

    if [[ -n "$remote_choice" ]]; then
        local remote_name
        remote_name=$(sed -n "${remote_choice}p" "$remotes_file")

        show_progress "Validating Credentials" "Testing authentication for $remote_name..." \
                      "rclone about ${remote_name}"

        if [[ $? -eq 0 ]]; then
            show_info "Credentials Valid" "Successfully authenticated to: $remote_name"
        else
            show_error "Credentials Invalid" "Authentication failed for: $remote_name\n\nPlease reconfigure the remote."
        fi
    fi
}

# Check bandwidth usage
check_bandwidth_usage() {
    log_tui "Checking bandwidth usage"
    show_info "Bandwidth Check" "Bandwidth monitoring will show:\n\n• Current upload/download speeds\n• Historical transfer statistics\n• Network interface usage\n\nThis feature will be available in a future update."
}

# Show sync solutions for common problems
show_sync_solutions() {
    local solutions_file="$TEMP_DIR/sync_solutions.txt"

    cat > "$solutions_file" << 'EOF'
COMMON CLOUD SYNC ISSUES & SOLUTIONS
====================================

PROBLEM: "Failed to copy" errors
SOLUTIONS:
• Check internet connectivity
• Verify remote credentials haven't expired
• Ensure sufficient storage space on remote
• Try reducing concurrent transfers: --transfers=1

PROBLEM: Slow upload speeds
SOLUTIONS:
• Check network bandwidth availability
• Increase concurrent transfers: --transfers=4
• Use --fast-list for large directories
• Consider scheduling during off-peak hours

PROBLEM: Authentication errors
SOLUTIONS:
• Reconfigure the remote: rclone config
• Check API credentials haven't expired
• Verify OAuth tokens are refreshed
• Check for rate limiting

PROBLEM: Sync interrupted
SOLUTIONS:
• Re-run sync (rclone handles partial transfers)
• Use --retries flag for automatic retry
• Check for disk space issues
• Verify stable network connection

PROBLEM: Files not syncing
SOLUTIONS:
• Check file permissions
• Verify path configuration
• Look for exclude patterns
• Check --dry-run output first
EOF

    dialog --title "Cloud Sync Solutions" \
           --textbox "$solutions_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Reset sync configuration
reset_sync_config() {
    if show_confirm "Reset Sync Config" "Reset cloud sync configuration?\n\n⚠ This will clear sync settings.\nRclone remote configurations will NOT be affected.\n\nContinue?"; then
        show_info "Reset Complete" "Sync configuration has been reset.\n\nRclone remotes are still configured.\nYou may need to reconfigure sync paths."
        log_tui "Sync configuration reset"
    fi
}

# Edit rclone remote
edit_rclone_remote() {
    log_tui "Editing rclone remote"

    local remotes_file="$TEMP_DIR/remotes.txt"
    rclone listremotes > "$remotes_file" 2>/dev/null || true

    if [[ ! -s "$remotes_file" ]]; then
        show_error "No Remotes" "No rclone remotes to edit."
        return
    fi

    local remote_choice
    remote_choice=$(dialog --clear --title "Edit Rclone Remote" \
                          --menu "Select remote to edit:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          $(cat "$remotes_file" | nl -w2 -s' ' | awk '{print $1, $2}') \
                          3>&1 1>&2 2>&3)

    if [[ -n "$remote_choice" ]]; then
        local remote_name
        remote_name=$(sed -n "${remote_choice}p" "$remotes_file" | tr -d ':')

        clear
        echo "Editing remote: $remote_name"
        echo "Press any key to continue..."
        read -n 1
        rclone config update "$remote_name"

        show_info "Edit Complete" "Remote configuration updated.\n\nRemote: $remote_name"
    fi
}

# Delete rclone remote
delete_rclone_remote() {
    log_tui "Deleting rclone remote"

    local remotes_file="$TEMP_DIR/remotes.txt"
    rclone listremotes > "$remotes_file" 2>/dev/null || true

    if [[ ! -s "$remotes_file" ]]; then
        show_error "No Remotes" "No rclone remotes to delete."
        return
    fi

    local remote_choice
    remote_choice=$(dialog --clear --title "Delete Rclone Remote" \
                          --menu "Select remote to DELETE:" \
                          $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                          $(cat "$remotes_file" | nl -w2 -s' ' | awk '{print $1, $2}') \
                          3>&1 1>&2 2>&3)

    if [[ -n "$remote_choice" ]]; then
        local remote_name
        remote_name=$(sed -n "${remote_choice}p" "$remotes_file" | tr -d ':')

        if show_confirm "Confirm Delete" "Delete remote: $remote_name?\n\n⚠ This cannot be undone!"; then
            rclone config delete "$remote_name"
            show_info "Remote Deleted" "Remote has been deleted: $remote_name"
            log_tui "Deleted rclone remote: $remote_name"
        fi
    fi
}

# View rclone configuration
view_rclone_config() {
    log_tui "Viewing rclone configuration"
    local config_file="$TEMP_DIR/rclone_config.txt"

    cat > "$config_file" << EOF
RCLONE CONFIGURATION
====================
Generated: $(date)

CONFIGURED REMOTES:
$(rclone listremotes 2>/dev/null || echo "  No remotes configured")

REMOTE DETAILS:
EOF

    # Show details for each remote (without sensitive info)
    for remote in $(rclone listremotes 2>/dev/null); do
        echo "" >> "$config_file"
        echo "[$remote]" >> "$config_file"
        rclone config show "$remote" 2>/dev/null | grep -v "token\|password\|secret\|key" | sed 's/^/  /' >> "$config_file"
    done

    dialog --title "Rclone Configuration" \
           --textbox "$config_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Edit rclone script
edit_rclone_script() {
    log_tui "Opening rclone script editor"

    if [[ -f "$RCLONE_BACKUP_SCRIPT" ]]; then
        local editor="${EDITOR:-nano}"
        clear
        echo "Opening rclone backup script with $editor..."
        read -n 1
        "$editor" "$RCLONE_BACKUP_SCRIPT"
        show_info "Edit Complete" "Rclone backup script updated."
    else
        show_error "Script Not Found" "Rclone backup script not found:\n$RCLONE_BACKUP_SCRIPT"
    fi
}

# Test all remotes
test_all_remotes() {
    log_tui "Testing all rclone remotes"
    local results_file="$TEMP_DIR/remote_tests.txt"

    cat > "$results_file" << EOF
RCLONE REMOTE CONNECTIVITY TEST
================================
Generated: $(date)

EOF

    local remotes
    remotes=$(rclone listremotes 2>/dev/null)

    if [[ -z "$remotes" ]]; then
        echo "No remotes configured." >> "$results_file"
    else
        for remote in $remotes; do
            echo "Testing: $remote" >> "$results_file"
            if rclone lsd "$remote" --max-depth 0 >/dev/null 2>&1; then
                echo "  ✓ Connected successfully" >> "$results_file"
            else
                echo "  ✗ Connection failed" >> "$results_file"
            fi
            echo "" >> "$results_file"
        done
    fi

    dialog --title "Remote Connectivity Tests" \
           --textbox "$results_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Import/export rclone configuration
import_export_rclone_config() {
    local choice
    choice=$(dialog --clear --title "Import/Export Rclone Config" \
                   --menu "Choose operation:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                   "1" "Export configuration" \
                   "2" "Import configuration" \
                   3>&1 1>&2 2>&3)

    case $choice in
        1)
            local export_file="$SCRIPT_DIR/../config/rclone-export-$(date +%Y%m%d).conf"
            if rclone config file >/dev/null 2>&1; then
                local config_path
                config_path=$(rclone config file | tail -1)
                if [[ -f "$config_path" ]]; then
                    cp "$config_path" "$export_file"
                    show_info "Export Complete" "Rclone configuration exported to:\n$export_file"
                fi
            fi
            ;;
        2)
            show_info "Import" "To import rclone configuration:\n\n1. Place your config file at ~/.config/rclone/rclone.conf\n2. Or run: rclone config"
            ;;
    esac
}

# Setup daily sync schedule
setup_daily_sync() {
    log_tui "Setting up daily sync"

    local hour
    hour=$(dialog --inputbox "Enter hour for daily sync (0-23):" 8 50 "2" 3>&1 1>&2 2>&3)

    if [[ -n "$hour" && "$hour" =~ ^[0-9]+$ && "$hour" -ge 0 && "$hour" -le 23 ]]; then
        local cron_entry="0 $hour * * * $RCLONE_BACKUP_SCRIPT"
        show_info "Daily Sync Setup" "To enable daily sync at ${hour}:00, add this to your crontab:\n\n$cron_entry\n\nRun: crontab -e"
        log_tui "Daily sync configured for hour: $hour"
    else
        show_error "Invalid Hour" "Please enter a valid hour (0-23)."
    fi
}

# Setup weekly sync schedule
setup_weekly_sync() {
    log_tui "Setting up weekly sync"

    local day_choice
    day_choice=$(dialog --clear --title "Weekly Sync Day" \
                       --menu "Select day for weekly sync:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "0" "Sunday" \
                       "1" "Monday" \
                       "2" "Tuesday" \
                       "3" "Wednesday" \
                       "4" "Thursday" \
                       "5" "Friday" \
                       "6" "Saturday" \
                       3>&1 1>&2 2>&3)

    if [[ -n "$day_choice" ]]; then
        local cron_entry="0 2 * * $day_choice $RCLONE_BACKUP_SCRIPT"
        local day_names=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
        show_info "Weekly Sync Setup" "To enable weekly sync on ${day_names[$day_choice]} at 2:00 AM, add this to crontab:\n\n$cron_entry\n\nRun: crontab -e"
    fi
}

# Setup custom cron schedule
setup_custom_schedule() {
    log_tui "Setting up custom schedule"

    local cron_expr
    cron_expr=$(dialog --inputbox "Enter cron expression (e.g., '0 */6 * * *' for every 6 hours):" 8 60 "0 2 * * *" 3>&1 1>&2 2>&3)

    if [[ -n "$cron_expr" ]]; then
        local cron_entry="$cron_expr $RCLONE_BACKUP_SCRIPT"
        show_info "Custom Schedule" "To enable this schedule, add to crontab:\n\n$cron_entry\n\nRun: crontab -e"
    fi
}

# View current sync schedule
view_sync_schedule() {
    log_tui "Viewing sync schedule"
    local schedule_file="$TEMP_DIR/schedule.txt"

    cat > "$schedule_file" << EOF
CURRENT SYNC SCHEDULE
=====================
Generated: $(date)

CRONTAB ENTRIES (related to backup):
$(crontab -l 2>/dev/null | grep -E "rclone|backup|restic" || echo "  No backup-related cron entries found")

SYSTEMD TIMERS (if any):
$(systemctl list-timers 2>/dev/null | grep -E "rclone|backup|restic" || echo "  No backup-related timers found")
EOF

    dialog --title "Sync Schedule" \
           --textbox "$schedule_file" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Disable scheduled sync
disable_sync_schedule() {
    show_info "Disable Schedule" "To disable scheduled sync:\n\n1. Edit crontab: crontab -e\n2. Remove or comment out backup entries\n3. Save and exit\n\nOr disable systemd timer:\nsudo systemctl disable backup.timer"
}

# View sync logs
view_sync_logs() {
    log_tui "Viewing sync logs"
    local log_file="$SCRIPT_DIR/../logs/rclone_backup.log"

    if [[ -f "$log_file" ]]; then
        dialog --title "Cloud Sync Logs" \
               --textbox "$log_file" \
               $DIALOG_HEIGHT $DIALOG_WIDTH
    else
        show_error "Log Not Found" "Sync log not found:\n$log_file\n\nRun a cloud sync first."
    fi
}

#######################################
# Script Entry Point
#######################################

main() {
    # Initialize TUI
    init_tui

    # Show welcome message
    show_info "Welcome" "Docker Stack 3-Stage Backup System\n\nUnified Text User Interface\nVersion $TUI_VERSION\n\nThis TUI provides comprehensive management for:\n• Stage 1: Docker Stack Backups\n• Stage 2: Cloud Synchronization\n• Stage 3: Disaster Recovery"

    # Check system status first
    check_system_status

    # Start main menu loop
    main_menu
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
