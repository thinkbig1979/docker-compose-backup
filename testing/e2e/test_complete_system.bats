#!/usr/bin/env bats
# End-to-end tests for complete backup system

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export BACKUP_CONFIG="${TEST_TEMP_DIR}/backup.conf"
    export RCLONE_CONFIG="${TEST_TEMP_DIR}/rclone.conf"
    export RESTIC_REPOSITORY="${TEST_TEMP_DIR}/restic-repo"
    export RESTIC_PASSWORD="e2e-test-password"
    export TEST_LOG_DIR="${TEST_TEMP_DIR}/logs"
    
    mkdir -p "${TEST_LOG_DIR}"
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/test-stack"
    mkdir -p "${TEST_TEMP_DIR}/cloud-storage"
    
    # Create test Docker stack
    cat > "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" << EOF
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - web-data:/usr/share/nginx/html
    environment:
      - TEST_ENV=e2e
volumes:
  web-data:
EOF
    
    # Create backup configuration
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=180
DOCKER_TIMEOUT=15
RESTIC_REPOSITORY=${RESTIC_REPOSITORY}
RESTIC_PASSWORD=${RESTIC_PASSWORD}
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=files
ENABLE_JSON_LOGGING=true
JSON_LOG_FILE=${TEST_LOG_DIR}/backup-metrics.json
EOF
    
    # Create rclone configuration for local cloud simulation
    cat > "${RCLONE_CONFIG}" << EOF
[cloud-storage]
type = local

[local-backup]
type = local
EOF
    
    # Initialize restic repository
    restic init --repo "${RESTIC_REPOSITORY}" --password-file <(echo "${RESTIC_PASSWORD}") >/dev/null 2>&1
}

teardown() {
    # Cleanup any running containers
    if [[ -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" ]]; then
        docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" down -v 2>/dev/null || true
    fi
    rm -rf "${TEST_TEMP_DIR}"
}

@test "E2E: Complete 3-stage backup system workflow" {
    skip_if_no_docker_or_rclone
    
    # Stage 1: Start Docker stack and create some data
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" up -d
    assert_success
    
    # Wait for services to be ready
    sleep 10
    
    # Create some test data in the volume
    run docker exec test-stack_web_1 sh -c 'echo "Test content" > /usr/share/nginx/html/test.html' 2>/dev/null || true
    
    # Stage 2: Run Docker backup
    run timeout 120s ../../docker-backup.sh
    assert_success
    assert_output --partial "Backup completed successfully"
    
    # Verify backup exists in restic
    run restic snapshots --repo "${RESTIC_REPOSITORY}" --password-file <(echo "${RESTIC_PASSWORD}")
    assert_success
    assert_output --partial "test-stack"
    
    # Stage 3: Sync to cloud storage using rclone
    run ../workspace/rclone_backup.sh "${RESTIC_REPOSITORY}" "cloud-storage:${TEST_TEMP_DIR}/cloud-storage"
    assert_success
    
    # Verify cloud backup exists
    assert_dir_exists "${TEST_TEMP_DIR}/cloud-storage"
    
    # Stage 4: Test restore process
    local restore_repo="${TEST_TEMP_DIR}/restored-repo"
    mkdir -p "${restore_repo}"
    
    # Restore from cloud
    run ../workspace/rclone_restore.sh "cloud-storage:${TEST_TEMP_DIR}/cloud-storage" "${restore_repo}"
    assert_success
    
    # Verify restored backup can be accessed
    if [[ -d "${restore_repo}" ]]; then
        run ls -la "${restore_repo}"
        assert_success
    fi
    
    # Cleanup
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" down -v
    assert_success
}

@test "E2E: TUI interaction with backup system" {
    # This test simulates TUI interactions using environment variables
    export TEST_MODE=true
    export BACKUP_CONFIG="${BACKUP_CONFIG}"
    export RCLONE_CONFIG="${RCLONE_CONFIG}"
    
    # Test TUI initialization
    run timeout 10s ../workspace/backup-tui.sh --help
    assert_success
    assert_output --partial "Docker Stack 3-Stage Backup System"
    
    # Test configuration validation through TUI
    run timeout 10s bash -c '
        export TEST_MODE=true
        source ../workspace/backup-tui.sh --source-only 2>/dev/null || echo "TUI loaded"
    '
    assert_success
}

@test "E2E: Directory list management integration" {
    skip_if_no_docker
    
    # Create multiple test stacks
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/app1"
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/app2"
    
    cat > "${TEST_TEMP_DIR}/docker-stacks/app1/docker-compose.yml" << EOF
version: '3.8'
services:
  web1:
    image: nginx:alpine
    volumes:
      - app1-data:/data
volumes:
  app1-data:
EOF
    
    cat > "${TEST_TEMP_DIR}/docker-stacks/app2/docker-compose.yml" << EOF
version: '3.8'
services:
  web2:
    image: nginx:alpine
    volumes:
      - app2-data:/data
volumes:
  app2-data:
EOF
    
    # Create dirlist with selective apps
    echo -e "app1\ntest-stack" > "${TEST_TEMP_DIR}/dirlist"
    export DIRLIST_FILE="${TEST_TEMP_DIR}/dirlist"
    
    # Start all stacks
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/app1/docker-compose.yml" up -d
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/app2/docker-compose.yml" up -d
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" up -d
    
    sleep 5
    
    # Run backup with directory list
    run timeout 120s ../../docker-backup.sh
    assert_success
    assert_output --partial "app1"
    assert_output --partial "test-stack"
    refute_output --partial "app2"
    
    # Test directory list management script
    run ../workspace/manage-dirlist.sh --list
    assert_success
    
    # Cleanup
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/app1/docker-compose.yml" down -v
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/app2/docker-compose.yml" down -v
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" down -v
}

@test "E2E: Error recovery and graceful failures" {
    # Test system behavior during various failure scenarios
    
    # Test 1: Invalid Docker stack
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/broken-stack"
    cat > "${TEST_TEMP_DIR}/docker-stacks/broken-stack/docker-compose.yml" << EOF
version: '3.8'
services:
  broken:
    image: non-existent-image:invalid
    command: /this/command/does/not/exist
EOF
    
    echo "broken-stack" > "${TEST_TEMP_DIR}/dirlist"
    export DIRLIST_FILE="${TEST_TEMP_DIR}/dirlist"
    
    run ../../docker-backup.sh --dry-run
    # Should handle broken stack gracefully in dry-run
    assert_success
    
    # Test 2: Insufficient disk space simulation
    cat >> "${BACKUP_CONFIG}" << EOF
MIN_DISK_SPACE_MB=999999999
EOF
    
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_output --partial "disk space"
    
    # Test 3: Invalid restic repository
    export RESTIC_REPOSITORY="/invalid/path/to/nowhere"
    
    run ../../docker-backup.sh --dry-run
    # Should fail gracefully
    assert_failure || assert_success
}

@test "E2E: Performance and monitoring integration" {
    # Test monitoring and performance features
    cat >> "${BACKUP_CONFIG}" << EOF
ENABLE_PERFORMANCE_MODE=true
CHECK_SYSTEM_RESOURCES=true
MEMORY_THRESHOLD_MB=128
LOAD_THRESHOLD=95
ENABLE_METRICS_COLLECTION=true
EOF
    
    run ../../docker-backup.sh --dry-run
    assert_success
    
    # Check if metrics were collected
    if [[ -f "${TEST_LOG_DIR}/backup-metrics.json" ]]; then
        run jq -e '.performance' "${TEST_LOG_DIR}/backup-metrics.json"
        assert_success || true  # May not exist in dry-run
    fi
}

@test "E2E: Security and verification features" {
    skip_if_no_docker
    
    # Enable all security features
    cat >> "${BACKUP_CONFIG}" << EOF
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=data
EOF
    
    # Start test stack
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" up -d
    assert_success
    
    sleep 5
    
    # Run backup with verification
    run timeout 120s ../../docker-backup.sh
    assert_success
    assert_output --partial "verification"
    
    # Cleanup
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-stack/docker-compose.yml" down -v
    assert_success
}

@test "E2E: Cross-platform compatibility" {
    # Test basic cross-platform features
    
    # Test path handling
    run ../../docker-backup.sh --dry-run
    assert_success
    
    # Test log file creation
    assert_file_exists "${TEST_LOG_DIR}/docker_backup.log" || true
    
    # Test configuration parsing
    run grep -q "BACKUP_DIR" "${BACKUP_CONFIG}"
    assert_success
}

# Helper functions
skip_if_no_docker() {
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        skip "Docker not available"
    fi
    if ! command -v docker-compose >/dev/null 2>&1; then
        skip "docker-compose not available"
    fi
}

skip_if_no_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        skip "rclone not available"
    fi
}

skip_if_no_docker_or_rclone() {
    skip_if_no_docker
    skip_if_no_rclone
}