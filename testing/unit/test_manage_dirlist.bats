#!/usr/bin/env bats
# Unit tests for manage-dirlist.sh

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_BACKUP_DIR="${TEST_TEMP_DIR}/docker-stacks"
    export BACKUP_CONFIG="${TEST_TEMP_DIR}/backup.conf"

    # Create test backup directory structure
    mkdir -p "${TEST_BACKUP_DIR}/app1"
    mkdir -p "${TEST_BACKUP_DIR}/app2"
    mkdir -p "${TEST_BACKUP_DIR}/app3"

    # Create sample docker-compose files
    for app in app1 app2 app3; do
        cat > "${TEST_BACKUP_DIR}/${app}/docker-compose.yml" << EOF
version: '3.8'
services:
  ${app}:
    image: nginx:alpine
EOF
    done

    # Create config file
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_BACKUP_DIR}
EOF
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}"
}

@test "manage-dirlist.sh exists and is executable" {
    run test -x "../workspace/manage-dirlist.sh"
    assert_success
}

@test "manage-dirlist.sh displays help when called with --help" {
    run ../workspace/manage-dirlist.sh --help
    assert_success
    assert_output --partial "Usage:"
}

@test "manage-dirlist.sh help shows prune option" {
    run ../workspace/manage-dirlist.sh --help
    assert_success
    assert_output --partial "prune"
}

@test "manage-dirlist.sh help shows prune-only option" {
    run ../workspace/manage-dirlist.sh --help
    assert_success
    assert_output --partial "prune-only"
}

@test "manage-dirlist.sh prune-only mode discovers directories" {
    run ../workspace/manage-dirlist.sh --prune-only
    assert_success
    # Should report discovered directories
    assert_output --partial "app1" || assert_output --partial "Docker compose directories" || assert_output --partial "Found"
}

@test "manage-dirlist.sh prune-only mode succeeds" {
    run ../workspace/manage-dirlist.sh --prune-only
    assert_success
}

@test "manage-dirlist.sh shows synchronization summary" {
    run ../workspace/manage-dirlist.sh --prune-only
    assert_success
    # Should show some summary information
    assert_output --partial "synchronized" || assert_output --partial "success" || assert_output --partial "completed" || assert_output --partial "SUCCESS"
}

@test "manage-dirlist.sh handles missing backup directory gracefully" {
    # Point to non-existent directory
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=/nonexistent/directory
EOF

    run ../workspace/manage-dirlist.sh --prune-only
    # Should fail or show error
    assert_failure
    assert_output --partial "not found" || assert_output --partial "does not exist" || assert_output --partial "ERROR"
}

@test "manage-dirlist.sh fails gracefully with unknown option" {
    run ../workspace/manage-dirlist.sh --unknown-option
    assert_failure
    assert_output --partial "Unknown" || assert_output --partial "error" || assert_output --partial "Usage"
}
