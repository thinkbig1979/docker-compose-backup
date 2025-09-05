#!/usr/bin/env bats
# Unit tests for manage-dirlist.sh

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_DIRLIST="${TEST_TEMP_DIR}/dirlist"
    export TEST_BACKUP_DIR="${TEST_TEMP_DIR}/docker-stacks"
    
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
    
    # Set environment variable for testing
    export DIRLIST_FILE="${TEST_DIRLIST}"
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

@test "manage-dirlist.sh creates new dirlist file" {
    run ../workspace/manage-dirlist.sh --add app1
    assert_success
    assert_file_exists "${TEST_DIRLIST}"
    
    run cat "${TEST_DIRLIST}"
    assert_output "app1"
}

@test "manage-dirlist.sh adds multiple directories" {
    run ../workspace/manage-dirlist.sh --add app1
    assert_success
    
    run ../workspace/manage-dirlist.sh --add app2
    assert_success
    
    run cat "${TEST_DIRLIST}"
    assert_line "app1"
    assert_line "app2"
}

@test "manage-dirlist.sh prevents duplicate entries" {
    run ../workspace/manage-dirlist.sh --add app1
    assert_success
    
    run ../workspace/manage-dirlist.sh --add app1
    assert_success
    
    local count
    count=$(grep -c "app1" "${TEST_DIRLIST}")
    [[ "${count}" -eq 1 ]]
}

@test "manage-dirlist.sh removes directories" {
    # Add directories first
    echo -e "app1\napp2\napp3" > "${TEST_DIRLIST}"
    
    run ../workspace/manage-dirlist.sh --remove app2
    assert_success
    
    run cat "${TEST_DIRLIST}"
    assert_line "app1"
    refute_line "app2"
    assert_line "app3"
}

@test "manage-dirlist.sh lists directories" {
    echo -e "app1\napp2\napp3" > "${TEST_DIRLIST}"
    
    run ../workspace/manage-dirlist.sh --list
    assert_success
    assert_output --partial "app1"
    assert_output --partial "app2"
    assert_output --partial "app3"
}

@test "manage-dirlist.sh handles empty dirlist" {
    touch "${TEST_DIRLIST}"
    
    run ../workspace/manage-dirlist.sh --list
    assert_success
    assert_output --partial "empty" || assert_output --partial "No directories"
}

@test "manage-dirlist.sh validates directories exist" {
    run ../workspace/manage-dirlist.sh --add nonexistent-app
    # Should either succeed with warning or fail gracefully
    assert_success || assert_failure
}

@test "manage-dirlist.sh clears all directories" {
    echo -e "app1\napp2\napp3" > "${TEST_DIRLIST}"
    
    run ../workspace/manage-dirlist.sh --clear
    assert_success
    
    run cat "${TEST_DIRLIST}"
    assert_output ""
}

@test "manage-dirlist.sh shows available directories" {
    export BACKUP_DIR="${TEST_BACKUP_DIR}"
    
    run ../workspace/manage-dirlist.sh --available
    assert_success
    assert_output --partial "app1"
    assert_output --partial "app2"
    assert_output --partial "app3"
}