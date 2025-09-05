#!/usr/bin/env bats
# Unit tests for docker-backup.sh

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

# Setup and teardown
setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export BACKUP_CONFIG="${TEST_TEMP_DIR}/backup.conf"
    export TEST_LOG_DIR="${TEST_TEMP_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Create test configuration
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=60
DOCKER_TIMEOUT=5
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    
    # Create test docker stacks directory
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/test-stack"
    cat > "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" << EOF
version: '3.8'
services:
  test:
    image: alpine:latest
    command: sleep 30
volumes:
  test-vol:
EOF
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}"
}

@test "docker-backup.sh exists and is executable" {
    run test -x "../../docker-backup.sh"
    assert_success
}

@test "docker-backup.sh displays help when called with --help" {
    run ../../docker-backup.sh --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "docker-backup.sh"
}

@test "docker-backup.sh fails without configuration file" {
    export BACKUP_CONFIG="/nonexistent/config"
    run ../../docker-backup.sh --dry-run
    assert_failure
    assert_output --partial "Configuration file not found"
}

@test "docker-backup.sh validates required configuration variables" {
    # Test missing BACKUP_DIR
    cat > "${BACKUP_CONFIG}" << EOF
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    
    run ../../docker-backup.sh --dry-run
    assert_failure
    assert_output --partial "BACKUP_DIR"
}

@test "docker-backup.sh validates backup directory exists" {
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=/nonexistent/directory
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    
    run ../../docker-backup.sh --dry-run
    assert_failure
    assert_output --partial "Backup directory does not exist"
}

@test "docker-backup.sh dry-run mode works correctly" {
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_output --partial "DRY RUN MODE"
    assert_output --partial "Found Docker compose directories"
}

@test "docker-backup.sh creates log directory if missing" {
    rm -rf "${TEST_LOG_DIR}"
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_dir_exists "${TEST_LOG_DIR}"
}

@test "docker-backup.sh handles PID file correctly" {
    local pid_file="${TEST_LOG_DIR}/docker_backup.pid"
    
    # Test PID file creation and cleanup in dry-run
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_file_not_exists "${pid_file}"
}

@test "docker-backup.sh validates restic repository" {
    # Initialize test repository
    export RESTIC_REPOSITORY="${TEST_TEMP_DIR}/restic-repo"
    export RESTIC_PASSWORD="test123"
    
    run restic init --repo "${RESTIC_REPOSITORY}" --password-file <(echo "test123")
    assert_success
    
    run ../../docker-backup.sh --dry-run
    assert_success
}

@test "docker-backup.sh handles timeout configuration" {
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=invalid
DOCKER_TIMEOUT=5
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    
    run ../../docker-backup.sh --dry-run
    # Should use default timeout when invalid value provided
    assert_success
}

@test "docker-backup.sh processes dirlist file when present" {
    local dirlist="${TEST_TEMP_DIR}/dirlist"
    echo "test-stack" > "${dirlist}"
    
    # Set DIRLIST_FILE environment variable
    export DIRLIST_FILE="${dirlist}"
    
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_output --partial "Using dirlist"
}

@test "docker-backup.sh validates disk space requirements" {
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=60
DOCKER_TIMEOUT=5
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
MIN_DISK_SPACE_MB=999999999
EOF
    
    run ../../docker-backup.sh --dry-run
    # Should warn about insufficient disk space
    assert_success
    assert_output --partial "disk space"
}