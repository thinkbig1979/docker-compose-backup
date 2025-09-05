#!/bin/bash

# Mock Commands Script for Docker Backup Testing
# This script provides mock implementations of docker and restic commands
# for testing the backup script without actual dependencies

# Configuration
MOCK_LOG_FILE="./logs/mock-commands.log"
MOCK_STATE_DIR="./logs/state"
DOCKER_FAIL_MODE="${DOCKER_FAIL_MODE:-false}"
RESTIC_FAIL_MODE="${RESTIC_FAIL_MODE:-false}"
DOCKER_DELAY="${DOCKER_DELAY:-1}"
RESTIC_DELAY="${RESTIC_DELAY:-2}"

# Ensure directories exist
mkdir -p "$(dirname "$MOCK_LOG_FILE")" "$MOCK_STATE_DIR"

# Logging function
mock_log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] MOCK: $*" >> "$MOCK_LOG_FILE"
    echo "MOCK: $*" >&2
}

# Mock docker command
mock_docker() {
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        "compose")
            mock_docker_compose "$@"
            ;;
        *)
            mock_log "Unknown docker subcommand: $subcommand"
            exit 1
            ;;
    esac
}

# Mock docker compose command
mock_docker_compose() {
    local action="$1"
    shift
    
    local current_dir
    current_dir="$(basename "$(pwd)")"
    
    case "$action" in
        "stop")
            mock_log "docker compose stop called in directory: $current_dir"
            
            if [[ "$DOCKER_FAIL_MODE" == "true" ]]; then
                mock_log "SIMULATED FAILURE: docker compose stop failed in $current_dir"
                exit 1
            fi
            
            # Simulate processing time
            sleep "$DOCKER_DELAY"
            
            # Create state file to track stopped containers
            echo "stopped" > "$MOCK_STATE_DIR/${current_dir}.state"
            mock_log "Successfully stopped containers in $current_dir"
            ;;
            
        "start")
            mock_log "docker compose start called in directory: $current_dir"
            
            # Check if containers were previously stopped
            if [[ ! -f "$MOCK_STATE_DIR/${current_dir}.state" ]]; then
                mock_log "WARNING: No state file found for $current_dir, containers may not have been stopped"
            fi
            
            if [[ "$DOCKER_FAIL_MODE" == "true" ]]; then
                mock_log "SIMULATED FAILURE: docker compose start failed in $current_dir"
                exit 1
            fi
            
            # Simulate processing time
            sleep "$DOCKER_DELAY"
            
            # Update state file
            echo "running" > "$MOCK_STATE_DIR/${current_dir}.state"
            mock_log "Successfully started containers in $current_dir"
            ;;
            
        "ps")
            mock_log "docker compose ps called in directory: $current_dir with args: $*"
            
            # Check if --services and --filter status=running are specified
            if [[ "$*" == *"--services"* && "$*" == *"--filter"* && "$*" == *"status=running"* ]]; then
                # Check state file to determine if containers are running
                if [[ -f "$MOCK_STATE_DIR/${current_dir}.state" ]]; then
                    local state
                    state="$(cat "$MOCK_STATE_DIR/${current_dir}.state")"
                    if [[ "$state" == "running" ]]; then
                        # Simulate running services
                        echo "web"
                        echo "db"
                        mock_log "Reported 2 running services for $current_dir"
                    else
                        # No running services
                        mock_log "Reported 0 running services for $current_dir (state: $state)"
                    fi
                else
                    # No state file means never started, so no running services
                    mock_log "Reported 0 running services for $current_dir (no state file)"
                fi
            else
                mock_log "docker compose ps called with unsupported arguments: $*"
                exit 1
            fi
            ;;
            
        *)
            mock_log "Unknown docker compose action: $action"
            exit 1
            ;;
    esac
}

# Mock restic command
mock_restic() {
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        "snapshots")
            mock_log "restic snapshots called with args: $*"
            
            if [[ "$RESTIC_FAIL_MODE" == "true" ]]; then
                mock_log "SIMULATED FAILURE: restic snapshots failed"
                exit 1
            fi
            
            # Simulate successful snapshots check
            mock_log "Repository access verified successfully"
            ;;
            
        "backup")
            mock_log "restic backup called with args: $*"
            
            # Extract directory being backed up (last argument)
            local backup_dir=""
            for arg in "$@"; do
                if [[ ! "$arg" =~ ^-- ]] && [[ "$arg" != "backup" ]]; then
                    backup_dir="$arg"
                fi
            done
            
            mock_log "Backing up directory: $backup_dir"
            
            if [[ "$RESTIC_FAIL_MODE" == "true" ]]; then
                mock_log "SIMULATED FAILURE: restic backup failed for $backup_dir"
                exit 1
            fi
            
            # Simulate backup progress
            echo "Files:           42 new,     0 changed,     0 unmodified"
            echo "Dirs:            12 new,     0 changed,     0 unmodified"
            echo "Added to the repo: 1.234 MiB"
            echo ""
            echo "processed 42 files, 1.234 MiB in 0:02"
            echo "snapshot 12345678 saved"
            
            # Simulate processing time
            sleep "$RESTIC_DELAY"
            
            # Create backup record
            local backup_record="$MOCK_STATE_DIR/backups.log"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed: $backup_dir" >> "$backup_record"
            mock_log "Successfully backed up: $backup_dir"
            ;;
            
        *)
            mock_log "Unknown restic subcommand: $subcommand"
            exit 1
            ;;
    esac
}

# Main command dispatcher
main() {
    local command="$1"
    shift
    
    case "$command" in
        "timeout")
            # Handle timeout command by extracting the actual command
            # Format: timeout DURATION COMMAND [ARGS...]
            local timeout_duration="$1"
            shift
            local actual_command="$1"
            shift
            
            mock_log "timeout $timeout_duration $actual_command called with args: $*"
            
            # Execute the actual command (recursively call main with the real command)
            main "$actual_command" "$@"
            ;;
        "docker")
            mock_docker "$@"
            ;;
        "restic")
            mock_restic "$@"
            ;;
        *)
            mock_log "Unknown command: $command"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"