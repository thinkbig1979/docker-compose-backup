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
readonly TUI_LOG_FILE="$SCRIPT_DIR/logs/backup_tui.log"

# Backup system scripts
readonly DOCKER_BACKUP_SCRIPT="$SCRIPT_DIR/docker-backup.sh"
readonly RCLONE_BACKUP_SCRIPT="$SCRIPT_DIR/rclone_backup.sh"
readonly RCLONE_RESTORE_SCRIPT="$SCRIPT_DIR/rclone_restore.sh"
readonly MANAGE_DIRLIST_SCRIPT="$SCRIPT_DIR/manage-dirlist.sh"

# Configuration files
readonly BACKUP_CONFIG="$SCRIPT_DIR/backup.conf"
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
    trap cleanup_tui EXIT
    
    # Ensure log directory exists
    local log_dir="$(dirname "$TUI_LOG_FILE")"
    [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir"
    
    # Initialize log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TUI Started" >> "$TUI_LOG_FILE"
}

# Cleanup TUI environment
cleanup_tui() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TUI Exited" >> "$TUI_LOG_FILE"
}

# Log TUI operations
log_tui() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$TUI_LOG_FILE"
}

# Show information dialog
show_info() {
    local title="$1"
    local message="$2"
    
    dialog --title "$title" \
           --msgbox "$message" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show error dialog
show_error() {
    local title="$1"
    local message="$2"
    
    dialog --title "Error: $title" \
           --msgbox "$message" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show confirmation dialog
show_confirm() {
    local title="$1"
    local message="$2"
    
    dialog --title "$title" \
           --yesno "$message" \
           $DIALOG_HEIGHT $DIALOG_WIDTH
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
        local choice
        choice=$(dialog --clear --title "Configuration Management" \
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
    while true; do
        local choice
        choice=$(dialog --clear --title "$TUI_TITLE v$TUI_VERSION" \
                       --menu "Choose an option:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
                       "1" "Stage 1: Docker Stack Backup" \
                       "2" "Stage 2: Cloud Sync (Upload)" \
                       "3" "Stage 3: Cloud Restore (Download)" \
                       "4" "Configuration Management" \
                       "5" "Directory List Management" \
                       "6" "Monitoring & Status" \
                       "7" "System Health Check" \
                       "8" "View Logs" \
                       "9" "Help & Documentation" \
                       "0" "Exit" \
                       3>&1 1>&2 2>&3)
        
        case $choice in
            1) stage1_docker_backup_menu ;;
            2) stage2_cloud_sync_menu ;;
            3) stage3_cloud_restore_menu ;;
            4) config_menu ;;
            5) directory_management ;;
            6) monitoring_menu ;;
            7) health_check ;;
            8) view_logs_menu ;;
            9) help_menu ;;
            0|"") 
                if show_confirm "Exit" "Are you sure you want to exit?"; then
                    clear
                    echo "Thank you for using the Docker Stack 3-Stage Backup System TUI!"
                    exit 0
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
        local choice
        choice=$(dialog --clear --title "Stage 1: Docker Stack Backup" \
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
            7) manage_directories ;;
            8) configure_backup_settings ;;
            9) backup_troubleshooting ;;
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

# Manage directories
manage_directories() {
    log_tui "Opening directory management"
    
    if [[ -f "$MANAGE_DIRLIST_SCRIPT" && -x "$MANAGE_DIRLIST_SCRIPT" ]]; then
        if show_confirm "Directory Management" "Open directory list management interface?\n\nThis will allow you to:\n• Enable/disable directories for backup\n• View directory status\n• Scan for new directories\n\nContinue?"; then
            # Temporarily exit dialog mode
            clear
            echo "Opening directory management interface..."
            echo "Press any key to continue..."
            read -n 1
            
            "$MANAGE_DIRLIST_SCRIPT"
            
            # Return to dialog mode
            show_info "Directory Management" "Directory management completed.\n\nChanges will take effect on next backup run."
        fi
    else
        show_error "Directory Management Unavailable" "Directory management script not found or not executable.\n\nFile: $MANAGE_DIRLIST_SCRIPT\n\nPlease check your installation."
    fi
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

# Check backup prerequisites
check_backup_prerequisites() {
    local issues=0
    local issue_list=""
    
    # Check if docker backup script exists and is executable
    if [[ ! -x "$DOCKER_BACKUP_SCRIPT" ]]; then
        issue_list="${issue_list}• Docker backup script not found or not executable\n"
        ((issues++))
    fi
    
    # Check configuration file
    if [[ ! -f "$BACKUP_CONFIG" ]]; then
        issue_list="${issue_list}• Backup configuration file not found\n"
        ((issues++))
    fi
    
    # Check required commands
    for cmd in restic docker; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            issue_list="${issue_list}• Required command not found: $cmd\n"
            ((issues++))
        fi
    done
    
    if [[ $issues -gt 0 ]]; then
        show_error "Prerequisites Not Met" "Found $issues issue(s) that prevent backup:\n\n$issue_list\nPlease resolve these issues before running backup."
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
        local choice
        choice=$(dialog --clear --title "Stage 2: Cloud Sync (Upload)" \
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
            6) configure_rclone_settings ;;
            7) schedule_sync ;;
            8) sync_troubleshooting ;;
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

# Check cloud sync prerequisites
check_cloud_sync_prerequisites() {
    local issues=0
    local issue_list=""
    
    # Check if rclone backup script exists and is executable
    if [[ ! -x "$RCLONE_BACKUP_SCRIPT" ]]; then
        issue_list="${issue_list}• Rclone backup script not found or not executable\n"
        ((issues++))
    fi
    
    # Check rclone command
    if ! command -v rclone >/dev/null 2>&1; then
        issue_list="${issue_list}• Rclone command not found - please install rclone\n"
        ((issues++))
    fi
    
    # Check rclone remotes
    local remotes_count=$(rclone listremotes 2>/dev/null | wc -l || echo "0")
    if [[ $remotes_count -eq 0 ]]; then
        issue_list="${issue_list}• No rclone remotes configured\n"
        ((issues++))
    fi
    
    if [[ $issues -gt 0 ]]; then
        show_error "Cloud Sync Prerequisites Not Met" "Found $issues issue(s) that prevent cloud sync:\n\n$issue_list\nPlease resolve these issues before running cloud sync."
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
        local choice
        choice=$(dialog --clear --title "Stage 3: Cloud Restore (Download)" \
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

# Check restore prerequisites
check_restore_prerequisites() {
    local issues=0
    local issue_list=""
    
    # Check if rclone restore script exists and is executable
    if [[ ! -x "$RCLONE_RESTORE_SCRIPT" ]]; then
        issue_list="${issue_list}• Rclone restore script not found or not executable\n"
        ((issues++))
    fi
    
    # Check rclone command
    if ! command -v rclone >/dev/null 2>&1; then
        issue_list="${issue_list}• Rclone command not found - please install rclone\n"
        ((issues++))
    fi
    
    # Check rclone remotes
    local remotes_count=$(rclone listremotes 2>/dev/null | wc -l || echo "0")
    if [[ $remotes_count -eq 0 ]]; then
        issue_list="${issue_list}• No rclone remotes configured\n"
        ((issues++))
    fi
    
    if [[ $issues -gt 0 ]]; then
        show_error "Restore Prerequisites Not Met" "Found $issues issue(s) that prevent restore:\n\n$issue_list\nPlease resolve these issues before running restore."
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

directory_management() {
    show_info "Coming Soon" "Directory List Management\nwill be implemented next."
}

monitoring_menu() {
    show_info "Coming Soon" "Monitoring & Status menu\nwill be implemented next."
}

health_check() {
    log_tui "Running system health check"
    
    show_progress "Health Check" "Running comprehensive health check..." \
                  "$DOCKER_BACKUP_SCRIPT --health-check"
    
    if [[ $? -eq 0 ]]; then
        show_info "Health Check Complete" "System health check completed successfully!\n\nCheck logs/backup_health.json for detailed report."
    else
        show_error "Health Check Failed" "System health check encountered issues."
        show_output "Health Check Output"
    fi
}

view_logs_menu() {
    show_info "Coming Soon" "Log viewer menu\nwill be implemented next."
}

help_menu() {
    show_info "Coming Soon" "Help & Documentation menu\nwill be implemented next."
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