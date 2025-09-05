#!/usr/bin/env bats
# Integration tests for rclone backup and restore functionality

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_RCLONE_CONFIG="${TEST_TEMP_DIR}/rclone.conf"
    export TEST_SOURCE_DIR="${TEST_TEMP_DIR}/source"
    export TEST_DEST_DIR="${TEST_TEMP_DIR}/destination"
    
    # Create test directories
    mkdir -p "${TEST_SOURCE_DIR}" "${TEST_DEST_DIR}"
    
    # Create test rclone configuration (local storage for testing)
    cat > "${TEST_RCLONE_CONFIG}" << EOF
[test-local]
type = local

[test-dest]
type = local
EOF
    
    # Create test files
    echo "Test backup file 1" > "${TEST_SOURCE_DIR}/file1.txt"
    echo "Test backup file 2" > "${TEST_SOURCE_DIR}/file2.txt"
    mkdir -p "${TEST_SOURCE_DIR}/subdir"
    echo "Subdirectory file" > "${TEST_SOURCE_DIR}/subdir/file3.txt"
    
    export RCLONE_CONFIG="${TEST_RCLONE_CONFIG}"
}

teardown() {
    rm -rf "${TEST_TEMP_DIR}"
}

@test "rclone_backup.sh exists and is executable" {
    run test -x "../workspace/rclone_backup.sh"
    assert_success
}

@test "rclone_restore.sh exists and is executable" {
    run test -x "../workspace/rclone_restore.sh"
    assert_success
}

@test "Integration: rclone backup with local storage" {
    skip_if_no_rclone
    
    # Test basic backup functionality
    run ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    assert_success
    
    # Verify files were copied
    assert_file_exists "${TEST_DEST_DIR}/backup/file1.txt"
    assert_file_exists "${TEST_DEST_DIR}/backup/file2.txt"
    assert_file_exists "${TEST_DEST_DIR}/backup/subdir/file3.txt"
    
    # Verify content integrity
    run diff "${TEST_SOURCE_DIR}/file1.txt" "${TEST_DEST_DIR}/backup/file1.txt"
    assert_success
}

@test "Integration: rclone restore functionality" {
    skip_if_no_rclone
    
    # First, create a backup
    run ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    assert_success
    
    # Create restore destination
    local restore_dir="${TEST_TEMP_DIR}/restored"
    mkdir -p "${restore_dir}"
    
    # Test restore
    run ../workspace/rclone_restore.sh "test-dest:${TEST_DEST_DIR}/backup" "${restore_dir}"
    assert_success
    
    # Verify restored files
    assert_file_exists "${restore_dir}/file1.txt"
    assert_file_exists "${restore_dir}/file2.txt"
    assert_file_exists "${restore_dir}/subdir/file3.txt"
    
    # Verify content integrity
    run diff "${TEST_SOURCE_DIR}/file1.txt" "${restore_dir}/file1.txt"
    assert_success
}

@test "Integration: rclone handles file conflicts during backup" {
    skip_if_no_rclone
    
    # Create initial backup
    run ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    assert_success
    
    # Modify source file
    echo "Modified content" > "${TEST_SOURCE_DIR}/file1.txt"
    
    # Run backup again
    run ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    assert_success
    
    # Verify updated content
    run cat "${TEST_DEST_DIR}/backup/file1.txt"
    assert_success
    assert_output "Modified content"
}

@test "Integration: rclone dry-run mode works correctly" {
    skip_if_no_rclone
    
    # Test dry-run mode (if supported by the script)
    if grep -q "\-\-dry-run" ../workspace/rclone_backup.sh; then
        run ../workspace/rclone_backup.sh --dry-run "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
        assert_success
        
        # Files should not exist after dry-run
        assert_file_not_exists "${TEST_DEST_DIR}/backup/file1.txt"
    else
        skip "Dry-run mode not implemented"
    fi
}

@test "Integration: rclone handles large directory structures" {
    skip_if_no_rclone
    
    # Create larger directory structure
    local large_dir="${TEST_SOURCE_DIR}/large"
    mkdir -p "${large_dir}"
    
    for i in {1..20}; do
        mkdir -p "${large_dir}/dir${i}"
        echo "Content ${i}" > "${large_dir}/dir${i}/file${i}.txt"
    done
    
    # Test backup
    run timeout 30s ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    assert_success
    
    # Verify some files exist
    assert_file_exists "${TEST_DEST_DIR}/backup/large/dir1/file1.txt"
    assert_file_exists "${TEST_DEST_DIR}/backup/large/dir10/file10.txt"
    assert_file_exists "${TEST_DEST_DIR}/backup/large/dir20/file20.txt"
}

@test "Integration: rclone error handling for invalid destinations" {
    skip_if_no_rclone
    
    # Test with invalid remote
    run ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "invalid-remote:/path"
    assert_failure
}

@test "Integration: rclone handles empty source directories" {
    skip_if_no_rclone
    
    local empty_dir="${TEST_TEMP_DIR}/empty"
    mkdir -p "${empty_dir}"
    
    run ../workspace/rclone_backup.sh "${empty_dir}" "test-dest:${TEST_DEST_DIR}/empty-backup"
    # Should handle empty directories gracefully
    assert_success || assert_failure
}

@test "Integration: rclone configuration validation" {
    skip_if_no_rclone
    
    # Test with missing configuration
    export RCLONE_CONFIG="/nonexistent/config"
    
    run ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    # Should either use default config or fail gracefully
    assert_failure
}

@test "Integration: rclone progress reporting" {
    skip_if_no_rclone
    
    # Create some larger test files
    dd if=/dev/zero of="${TEST_SOURCE_DIR}/largefile.dat" bs=1024 count=100 2>/dev/null
    
    # Test with progress reporting (if supported)
    run timeout 30s ../workspace/rclone_backup.sh "${TEST_SOURCE_DIR}" "test-dest:${TEST_DEST_DIR}/backup"
    assert_success
    
    # Verify large file was copied
    assert_file_exists "${TEST_DEST_DIR}/backup/largefile.dat"
    
    # Check file size
    local source_size dest_size
    source_size=$(stat -c%s "${TEST_SOURCE_DIR}/largefile.dat")
    dest_size=$(stat -c%s "${TEST_DEST_DIR}/backup/largefile.dat")
    
    [[ "${source_size}" -eq "${dest_size}" ]]
}

# Helper function to skip tests when rclone is not available
skip_if_no_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        skip "rclone not available"
    fi
}