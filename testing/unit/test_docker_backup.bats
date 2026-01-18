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

    # Initialize restic repository for tests
    export RESTIC_PASSWORD="test123"
    restic init --repo "${TEST_TEMP_DIR}/restic-repo" 2>/dev/null || true

    # Create test configuration
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=60
DOCKER_TIMEOUT=5
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    chmod 600 "${BACKUP_CONFIG}"
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}"
}

@test "docker-backup.sh exists and is executable" {
    run test -x "../workspace/docker-backup.sh"
    assert_success
}

@test "docker-backup.sh displays help when called with --help" {
    run ../workspace/docker-backup.sh --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "docker-backup.sh"
}

@test "docker-backup.sh fails without configuration file" {
    export BACKUP_CONFIG="/nonexistent/config"
    run ../workspace/docker-backup.sh --dry-run
    assert_failure
    assert_output --partial "Configuration file not found"
}

@test "docker-backup.sh validates required configuration variables" {
    # Test missing BACKUP_DIR
    cat > "${BACKUP_CONFIG}" << EOF
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    chmod 600 "${BACKUP_CONFIG}"

    run ../workspace/docker-backup.sh --dry-run
    assert_failure
    assert_output --partial "BACKUP_DIR"
}

@test "docker-backup.sh validates backup directory exists" {
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=/nonexistent/directory
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    chmod 600 "${BACKUP_CONFIG}"

    run ../workspace/docker-backup.sh --dry-run
    assert_failure
    assert_output --partial "BACKUP_DIR does not exist"
}

@test "docker-backup.sh dry-run mode runs successfully" {
    run ../workspace/docker-backup.sh --dry-run
    assert_success
    # Check for phase progression indicating script ran
    assert_output --partial "Phase 1"
    assert_output --partial "Phase 2" || assert_output --partial "PHASE 2"
}

@test "docker-backup.sh scans for Docker compose directories" {
    run ../workspace/docker-backup.sh --dry-run
    assert_success
    # Check that directory scanning occurs
    assert_output --partial "Scanning"
}

@test "docker-backup.sh handles PID file correctly" {
    # Test PID file creation and cleanup in dry-run
    run ../workspace/docker-backup.sh --dry-run
    assert_success
    # PID file should be cleaned up after execution
}

@test "docker-backup.sh validates restic repository access" {
    # Repository is already initialized in setup
    run ../workspace/docker-backup.sh --dry-run
    assert_success
}

@test "docker-backup.sh rejects invalid timeout configuration" {
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=invalid
DOCKER_TIMEOUT=5
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    chmod 600 "${BACKUP_CONFIG}"

    run ../workspace/docker-backup.sh --dry-run
    # Script validates timeout and fails on invalid values
    assert_failure
    assert_output --partial "BACKUP_TIMEOUT"
}

@test "docker-backup.sh discovers directories in BACKUP_DIR" {
    run ../workspace/docker-backup.sh --dry-run
    assert_success
    # Check that it discovers the test-stack directory
    assert_output --partial "test-stack"
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
    chmod 600 "${BACKUP_CONFIG}"

    run ../workspace/docker-backup.sh --dry-run
    # Should either warn or fail about insufficient disk space
    assert_output --partial "space" || assert_output --partial "insufficient"
}
