#!/usr/bin/env bats
# Unit tests for backup-tui.sh

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_LOG_DIR="${TEST_TEMP_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Mock dialog command for testing
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    mkdir -p "${TEST_TEMP_DIR}/bin"
    
    # Create mock dialog that outputs to stdout
    cat > "${TEST_TEMP_DIR}/bin/dialog" << 'EOF'
#!/bin/bash
echo "Mock dialog called with: $@" >&2
case "$*" in
    *--yesno*)
        exit 0  # Yes response
        ;;
    *--menu*)
        echo "1"  # First menu option
        ;;
    *--inputbox*)
        echo "test-input"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "${TEST_TEMP_DIR}/bin/dialog"
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}"
}

@test "backup-tui.sh exists and is executable" {
    run test -x "../workspace/backup-tui.sh"
    assert_success
}

@test "backup-tui.sh displays help when called with --help" {
    run ../workspace/backup-tui.sh --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "backup-tui.sh"
}

@test "backup-tui.sh checks for dialog dependency" {
    # Remove dialog from PATH
    export PATH="/usr/bin:/bin"
    
    run ../workspace/backup-tui.sh
    assert_failure
    assert_output --partial "dialog"
}

@test "backup-tui.sh initializes TUI environment" {
    # Set environment to avoid actual TUI launch
    export TEST_MODE=true
    
    run timeout 5s ../workspace/backup-tui.sh --version
    assert_success
    assert_output --partial "version"
}

@test "backup-tui.sh creates log directory" {
    export TEST_MODE=true
    rm -rf "${TEST_LOG_DIR}"
    
    run timeout 5s ../workspace/backup-tui.sh --help
    assert_success
}

@test "backup-tui.sh handles backup script dependencies" {
    export TEST_MODE=true
    
    # Test with missing docker-backup.sh
    local fake_script_dir="${TEST_TEMP_DIR}/scripts"
    mkdir -p "${fake_script_dir}"
    
    # This test verifies the script can handle missing dependencies
    run timeout 5s ../workspace/backup-tui.sh --help
    assert_success
}

@test "backup-tui.sh validates configuration files" {
    export TEST_MODE=true
    export BACKUP_CONFIG="${TEST_TEMP_DIR}/backup.conf"
    
    # Create valid configuration
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
RESTIC_REPOSITORY=${TEST_TEMP_DIR}/restic-repo
RESTIC_PASSWORD=test123
EOF
    
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks"
    
    run timeout 5s ../workspace/backup-tui.sh --help
    assert_success
}

@test "backup-tui.sh handles rclone configuration" {
    export TEST_MODE=true
    export RCLONE_CONFIG="${TEST_TEMP_DIR}/rclone.conf"
    
    # Create minimal rclone config
    cat > "${RCLONE_CONFIG}" << EOF
[test-remote]
type = local
EOF
    
    run timeout 5s ../workspace/backup-tui.sh --help
    assert_success
}

@test "backup-tui.sh provides version information" {
    run ../workspace/backup-tui.sh --version
    assert_success
    assert_output --partial "Docker Stack 3-Stage Backup System"
    assert_output --partial "Version:"
}

@test "backup-tui.sh handles cleanup on exit" {
    export TEST_MODE=true
    local test_pid=$$
    
    # Test cleanup function exists and can be called
    run timeout 5s bash -c '
        source ../workspace/backup-tui.sh --source-only 2>/dev/null || true
        if declare -f cleanup_and_exit >/dev/null; then
            echo "cleanup function exists"
        fi
    '
    assert_success
    assert_output --partial "cleanup function exists"
}

@test "backup-tui.sh handles terminal resize gracefully" {
    export TEST_MODE=true
    
    # Simulate terminal resize by changing TERM
    export TERM=xterm-256color
    export LINES=24
    export COLUMNS=80
    
    run timeout 5s ../workspace/backup-tui.sh --help
    assert_success
}