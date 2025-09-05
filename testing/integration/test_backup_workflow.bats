#!/usr/bin/env bats
# Integration tests for complete backup workflow

load "${BATS_LIB_PATH}/bats-support/load.bash"
load "${BATS_LIB_PATH}/bats-assert/load.bash"
load "${BATS_LIB_PATH}/bats-file/load.bash"

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export BACKUP_CONFIG="${TEST_TEMP_DIR}/backup.conf"
    export RESTIC_REPOSITORY="${TEST_TEMP_DIR}/restic-repo"
    export RESTIC_PASSWORD="test-integration-123"
    export TEST_LOG_DIR="${TEST_TEMP_DIR}/logs"
    
    mkdir -p "${TEST_LOG_DIR}"
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/test-app"
    
    # Create test Docker compose stack
    cat > "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" << EOF
version: '3.8'
services:
  web:
    image: nginx:alpine
    volumes:
      - web-data:/usr/share/nginx/html
volumes:
  web-data:
EOF
    
    # Create test configuration
    cat > "${BACKUP_CONFIG}" << EOF
BACKUP_DIR=${TEST_TEMP_DIR}/docker-stacks
BACKUP_TIMEOUT=120
DOCKER_TIMEOUT=10
RESTIC_REPOSITORY=${RESTIC_REPOSITORY}
RESTIC_PASSWORD=${RESTIC_PASSWORD}
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=files
MIN_DISK_SPACE_MB=10
EOF
    
    # Initialize restic repository
    run restic init --repo "${RESTIC_REPOSITORY}" --password-file <(echo "${RESTIC_PASSWORD}")
    assert_success
}

teardown() {
    # Cleanup any running containers
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" down -v 2>/dev/null || true
    rm -rf "${TEST_TEMP_DIR}"
}

@test "Integration: Full backup workflow with Docker stack" {
    skip_if_no_docker
    
    # Start test stack
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" up -d
    assert_success
    
    # Wait for stack to be ready
    sleep 5
    
    # Run backup
    run timeout 60s ../../docker-backup.sh
    assert_success
    assert_output --partial "Backup completed successfully"
    
    # Verify backup was created
    run restic snapshots --repo "${RESTIC_REPOSITORY}" --password-file <(echo "${RESTIC_PASSWORD}")
    assert_success
    assert_output --partial "test-app"
    
    # Stop test stack
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" down -v
    assert_success
}

@test "Integration: Backup with dirlist filtering" {
    skip_if_no_docker
    
    # Create additional stack that should be ignored
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/ignored-app"
    cat > "${TEST_TEMP_DIR}/docker-stacks/ignored-app/docker-compose.yml" << EOF
version: '3.8'
services:
  ignored:
    image: alpine:latest
EOF
    
    # Create dirlist with only test-app
    echo "test-app" > "${TEST_TEMP_DIR}/dirlist"
    export DIRLIST_FILE="${TEST_TEMP_DIR}/dirlist"
    
    # Start both stacks
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" up -d
    assert_success
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/ignored-app/docker-compose.yml" up -d
    assert_success
    
    sleep 5
    
    # Run backup
    run timeout 60s ../../docker-backup.sh
    assert_success
    assert_output --partial "Using dirlist"
    assert_output --partial "test-app"
    refute_output --partial "ignored-app"
    
    # Cleanup
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" down -v
    docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/ignored-app/docker-compose.yml" down -v
}

@test "Integration: Backup verification works correctly" {
    skip_if_no_docker
    
    # Start test stack
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" up -d
    assert_success
    
    sleep 5
    
    # Run backup with verification enabled
    run timeout 60s ../../docker-backup.sh
    assert_success
    assert_output --partial "Backup verification"
    assert_output --partial "Verification completed successfully"
    
    # Stop test stack
    run docker-compose -f "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" down -v
    assert_success
}

@test "Integration: Error handling for missing Docker stack" {
    # Create configuration pointing to non-existent stack
    mkdir -p "${TEST_TEMP_DIR}/docker-stacks/missing-stack"
    # No docker-compose.yml file
    
    echo "missing-stack" > "${TEST_TEMP_DIR}/dirlist"
    export DIRLIST_FILE="${TEST_TEMP_DIR}/dirlist"
    
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_output --partial "No docker-compose.yml found"
}

@test "Integration: Handles Docker service start failure gracefully" {
    skip_if_no_docker
    
    # Create invalid Docker compose file
    cat > "${TEST_TEMP_DIR}/docker-stacks/test-app/docker-compose.yml" << EOF
version: '3.8'
services:
  broken:
    image: non-existent-image:latest
    command: this-will-fail
EOF
    
    # Should handle the failure gracefully
    run timeout 30s ../../docker-backup.sh --dry-run
    # Dry run should succeed even with broken compose file
    assert_success
}

@test "Integration: Resource monitoring integration" {
    cat >> "${BACKUP_CONFIG}" << EOF
CHECK_SYSTEM_RESOURCES=true
MEMORY_THRESHOLD_MB=1
LOAD_THRESHOLD=1
EOF
    
    run ../../docker-backup.sh --dry-run
    assert_success
    assert_output --partial "resource"
}

@test "Integration: JSON logging integration" {
    local json_log="${TEST_TEMP_DIR}/backup-metrics.json"
    
    cat >> "${BACKUP_CONFIG}" << EOF
ENABLE_JSON_LOGGING=true
JSON_LOG_FILE=${json_log}
EOF
    
    run ../../docker-backup.sh --dry-run
    assert_success
    
    if [[ -f "${json_log}" ]]; then
        run jq . "${json_log}"
        assert_success
    fi
}

# Helper function to skip tests when Docker is not available
skip_if_no_docker() {
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        skip "Docker not available"
    fi
}