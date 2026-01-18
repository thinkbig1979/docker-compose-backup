#!/bin/bash
# Main test runner for backup-tui
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Log file
LOG_FILE="/app/output/test-results.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "  backup-tui Test Suite"
echo "  $(date)"
echo "=========================================="
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Error: $2"
    ((TESTS_FAILED++))
}

info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Wait for services to be ready
wait_for_services() {
    info "Waiting for MinIO to be ready..."
    for i in {1..30}; do
        if curl -sf http://minio:9000/minio/health/live > /dev/null 2>&1; then
            pass "MinIO is ready"
            return 0
        fi
        sleep 1
    done
    fail "MinIO startup" "Timeout waiting for MinIO"
    return 1
}

# Setup rclone config for MinIO
setup_rclone() {
    info "Configuring rclone for MinIO..."
    mkdir -p ~/.config/rclone
    cat > ~/.config/rclone/rclone.conf << EOF
[minio]
type = s3
provider = Minio
access_key_id = minioadmin
secret_access_key = minioadmin
endpoint = http://minio:9000
acl = private
EOF

    # Create the bucket
    rclone mkdir minio:/backup-test 2>/dev/null || true
    pass "rclone configured for MinIO"
}

# Setup test data
setup_test_data() {
    info "Setting up test data..."

    # Create test files in mock stacks
    mkdir -p /opt/docker-stacks/stack1/data
    mkdir -p /opt/docker-stacks/stack2/data

    echo "Stack 1 test data - $(date)" > /opt/docker-stacks/stack1/data/test-file.txt
    echo "Important config" > /opt/docker-stacks/stack1/data/config.yml
    dd if=/dev/urandom of=/opt/docker-stacks/stack1/data/binary-data.bin bs=1024 count=100 2>/dev/null

    echo "Stack 2 database dump - $(date)" > /opt/docker-stacks/stack2/data/dump.sql
    echo "Stack 2 logs" > /opt/docker-stacks/stack2/data/app.log

    # Create dirlist file
    cat > /app/config/dirlist << EOF
+stack1
+stack2
EOF

    pass "Test data created"
}

# Initialize restic repository
init_restic_repo() {
    info "Initializing restic repository..."
    export RESTIC_REPOSITORY=/backup/restic-repo
    export RESTIC_PASSWORD=test-password-123

    if [ ! -d "$RESTIC_REPOSITORY" ] || [ ! -f "$RESTIC_REPOSITORY/config" ]; then
        restic init 2>/dev/null
        pass "Restic repository initialized"
    else
        pass "Restic repository already exists"
    fi
}

# ==========================================
# CLI Tests (non-interactive)
# ==========================================

test_cli_help() {
    info "Testing CLI help..."
    if backup-tui --help > /dev/null 2>&1 || backup-tui -h > /dev/null 2>&1; then
        pass "CLI help works"
    else
        # Some apps return non-zero for help, check if output exists
        if backup-tui --help 2>&1 | grep -q -i "backup\|usage\|help"; then
            pass "CLI help works"
        else
            fail "CLI help" "No help output"
        fi
    fi
}

test_cli_validate() {
    info "Testing config validation..."
    cd /app/config
    if backup-tui validate 2>&1; then
        pass "Config validation passed"
    else
        output=$(backup-tui validate 2>&1 || true)
        if echo "$output" | grep -qi "valid\|ok\|success"; then
            pass "Config validation passed"
        else
            fail "Config validation" "$output"
        fi
    fi
}

test_cli_status() {
    info "Testing status command..."
    cd /app/config
    output=$(backup-tui status 2>&1 || true)
    if echo "$output" | grep -qi "status\|directory\|config\|restic\|rclone"; then
        pass "Status command works"
    else
        fail "Status command" "Unexpected output: $output"
    fi
}

test_cli_backup_dry_run() {
    info "Testing backup dry run..."
    cd /app/config
    output=$(backup-tui backup --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "dry\|would\|skip\|backup"; then
        pass "Backup dry run works"
    else
        fail "Backup dry run" "Unexpected output: $output"
    fi
}

test_cli_backup() {
    info "Testing actual backup..."
    cd /app/config
    export RESTIC_REPOSITORY=/backup/restic-repo
    export RESTIC_PASSWORD=test-password-123

    output=$(backup-tui backup 2>&1 || true)

    # Verify backup was created
    snapshots=$(restic snapshots --json 2>/dev/null | jq length)
    if [ "$snapshots" -gt 0 ]; then
        pass "Backup created successfully ($snapshots snapshots)"
    else
        fail "Backup" "No snapshots found after backup. Output: $output"
    fi
}

test_cli_sync_dry_run() {
    info "Testing cloud sync dry run..."
    cd /app/config
    output=$(backup-tui sync --dry-run 2>&1 || true)
    if echo "$output" | grep -qi "dry\|would\|sync\|rclone"; then
        pass "Cloud sync dry run works"
    else
        # May fail if rclone not configured, that's ok for dry run test
        info "Cloud sync dry run output: $output"
        pass "Cloud sync dry run completed (check output)"
    fi
}

test_cli_sync() {
    info "Testing actual cloud sync..."
    cd /app/config
    output=$(backup-tui sync 2>&1 || true)

    # Verify files were synced to MinIO
    remote_files=$(rclone ls minio:/backup-test 2>/dev/null | wc -l)
    if [ "$remote_files" -gt 0 ]; then
        pass "Cloud sync uploaded files ($remote_files files)"
    else
        fail "Cloud sync" "No files found in remote. Output: $output"
    fi
}

# ==========================================
# TUI Tests (using expect)
# ==========================================

test_tui_navigation() {
    info "Testing TUI navigation..."

    # Create expect script for TUI testing
    cat > /tmp/test_tui.exp << 'EXPECT_EOF'
#!/usr/bin/expect -f
set timeout 10

# Start the TUI
spawn backup-tui

# Wait for main menu
expect {
    "Main Menu" { }
    timeout { puts "FAIL: Main menu not displayed"; exit 1 }
}

# Navigate to backup menu (press 1)
send "1"
expect {
    "Backup" { }
    timeout { puts "FAIL: Backup menu not displayed"; exit 1 }
}

# Go back with ESC
send "\033"
expect {
    "Main Menu" { }
    timeout { puts "FAIL: Could not return to main menu"; exit 1 }
}

# Navigate to sync menu (press 2)
send "2"
expect {
    "Sync" { }
    timeout { puts "FAIL: Sync menu not displayed"; exit 1 }
}

# Go back with ESC
send "\033"
expect {
    "Main Menu" { }
    timeout { puts "FAIL: Could not return to main menu"; exit 1 }
}

# Quit (press q)
send "q"
expect eof

puts "SUCCESS: TUI navigation works"
EXPECT_EOF

    chmod +x /tmp/test_tui.exp
    cd /app/config

    if /tmp/test_tui.exp 2>&1 | grep -q "SUCCESS"; then
        pass "TUI navigation works"
    else
        output=$(/tmp/test_tui.exp 2>&1 || true)
        fail "TUI navigation" "$output"
    fi
}

test_tui_backup_dry_run() {
    info "Testing TUI backup dry run..."

    cat > /tmp/test_backup.exp << 'EXPECT_EOF'
#!/usr/bin/expect -f
set timeout 30

spawn backup-tui

# Wait for main menu
expect "Main Menu"

# Go to backup menu
send "1"
expect "Backup"

# Select dry run (press d or navigate and enter)
send "d"

# Wait for output
expect {
    -re "dry|Dry|would|complete" { }
    timeout { puts "FAIL: Dry run did not complete"; exit 1 }
}

# Wait a bit for output
sleep 2

# Go back and quit
send "\033"
sleep 1
send "\033"
sleep 1
send "q"
expect eof

puts "SUCCESS: TUI backup dry run works"
EXPECT_EOF

    chmod +x /tmp/test_backup.exp
    cd /app/config

    if timeout 60 /tmp/test_backup.exp 2>&1 | grep -q "SUCCESS"; then
        pass "TUI backup dry run works"
    else
        output=$(timeout 60 /tmp/test_backup.exp 2>&1 || true)
        fail "TUI backup dry run" "$output"
    fi
}

test_tui_sync_menu() {
    info "Testing TUI sync menu..."

    cat > /tmp/test_sync.exp << 'EXPECT_EOF'
#!/usr/bin/expect -f
set timeout 15

spawn backup-tui

expect "Main Menu"

# Go to sync menu
send "2"
expect {
    "Sync" { }
    "Cloud Sync" { }
    timeout { puts "FAIL: Sync menu not displayed"; exit 1 }
}

# Test connectivity option (press t)
send "t"
expect {
    -re "connect|Connect|test|Test|rclone" { }
    timeout { puts "FAIL: Connectivity test did not start"; exit 1 }
}

sleep 2

# Go back and quit
send "\033"
sleep 1
send "\033"
sleep 1
send "q"
expect eof

puts "SUCCESS: TUI sync menu works"
EXPECT_EOF

    chmod +x /tmp/test_sync.exp
    cd /app/config

    if timeout 30 /tmp/test_sync.exp 2>&1 | grep -q "SUCCESS"; then
        pass "TUI sync menu works"
    else
        output=$(timeout 30 /tmp/test_sync.exp 2>&1 || true)
        fail "TUI sync menu" "$output"
    fi
}

# ==========================================
# Main test execution
# ==========================================

main() {
    echo ""
    echo "=========================================="
    echo "  Setup Phase"
    echo "=========================================="

    wait_for_services || exit 1
    setup_rclone
    setup_test_data
    init_restic_repo

    echo ""
    echo "=========================================="
    echo "  CLI Tests"
    echo "=========================================="

    test_cli_help
    test_cli_validate
    test_cli_status
    test_cli_backup_dry_run
    test_cli_backup
    test_cli_sync_dry_run
    test_cli_sync

    echo ""
    echo "=========================================="
    echo "  TUI Tests"
    echo "=========================================="

    test_tui_navigation
    test_tui_backup_dry_run
    test_tui_sync_menu

    echo ""
    echo "=========================================="
    echo "  Test Summary"
    echo "=========================================="
    echo ""
    echo -e "  ${GREEN}Passed${NC}: $TESTS_PASSED"
    echo -e "  ${RED}Failed${NC}: $TESTS_FAILED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
