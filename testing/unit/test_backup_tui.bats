#!/usr/bin/env bats
# Unit tests for backup-tui.sh
# Note: backup-tui.sh is a TUI application using dialog
# These tests focus on non-interactive aspects only

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}"
}

@test "backup-tui.sh exists and is executable" {
    run test -x "../workspace/backup-tui.sh"
    assert_success
}

@test "backup-tui.sh has valid bash syntax" {
    run bash -n "../workspace/backup-tui.sh"
    assert_success
}

@test "backup-tui.sh contains expected version string" {
    run grep -q "Version" "../workspace/backup-tui.sh"
    assert_success
}

@test "backup-tui.sh contains main function" {
    run grep -q "main()" "../workspace/backup-tui.sh"
    assert_success
}

@test "backup-tui.sh contains dialog function" {
    run grep -q "dialog" "../workspace/backup-tui.sh"
    assert_success
}
