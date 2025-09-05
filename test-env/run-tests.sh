#!/bin/bash

# Test Runner for Docker Backup Script
# Comprehensive test suite for validating backup script functionality
# without requiring Docker or restic dependencies

# Bash strict mode
set -eo pipefail

# Test configuration
readonly TEST_SCRIPT="./docker-backup-test.sh"
readonly TEST_CONFIG="./test-backup.conf"
readonly TEST_LOG_DIR="./logs"
readonly TEST_DIRLIST="./dirlist"
readonly MOCK_LOG="$TEST_LOG_DIR/mock-commands.log"
readonly TEST_RESULTS_LOG="$TEST_LOG_DIR/test-results.log"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

#######################################
# Test Framework Functions
#######################################

# Initialize test environment
init_test_env() {
    echo -e "${CYAN}=== Initializing Test Environment ===${NC}"
    
    # Clean up previous test runs
    rm -f "$TEST_LOG_DIR"/*.log "$TEST_LOG_DIR"/*.pid "$TEST_DIRLIST" 2>/dev/null || true
    rm -rf "$TEST_LOG_DIR/state" 2>/dev/null || true
    
    # Ensure directories exist
    mkdir -p "$TEST_LOG_DIR"
    
    # Initialize test results log
    echo "Test Results - $(date '+%Y-%m-%d %H:%M:%S')" > "$TEST_RESULTS_LOG"
    echo "================================================" >> "$TEST_RESULTS_LOG"
    
    echo -e "${GREEN}Test environment initialized${NC}"
}

# Log test result
log_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$result" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        echo "PASS: $test_name" >> "$TEST_RESULTS_LOG"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "FAIL: $test_name" >> "$TEST_RESULTS_LOG"
        if [[ -n "$details" ]]; then
            echo -e "${YELLOW}  Details: $details${NC}"
            echo "  Details: $details" >> "$TEST_RESULTS_LOG"
        fi
    fi
    
    echo "" >> "$TEST_RESULTS_LOG"
}

# Run a test with expected outcome
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    local check_function="${4:-}"
    
    echo -e "${BLUE}Running test: $test_name${NC}"
    
    # Clean up before each test
    rm -f "$TEST_LOG_DIR"/*.log "$TEST_LOG_DIR"/*.pid 2>/dev/null || true
    rm -rf "$TEST_LOG_DIR/state" 2>/dev/null || true
    
    # Run the test command directly without timeout to avoid hanging
    local actual_exit_code=0
    eval "$test_command" >/dev/null 2>&1 || actual_exit_code=$?
    
    # Check exit code
    if [[ $actual_exit_code -ne $expected_exit_code ]]; then
        log_test_result "$test_name" "FAIL" "Expected exit code $expected_exit_code, got $actual_exit_code"
        return 1
    fi
    
    # Run additional checks if provided
    if [[ -n "$check_function" ]]; then
        if ! $check_function >/dev/null 2>&1; then
            log_test_result "$test_name" "FAIL" "Check function failed"
            return 1
        fi
    fi
    
    log_test_result "$test_name" "PASS"
    return 0
}

#######################################
# Test Check Functions
#######################################

# Check if directories were discovered correctly
check_directory_discovery() {
    if [[ ! -f "$TEST_DIRLIST" ]]; then
        echo "Directory list file not created"
        return 1
    fi
    
    # Check if all expected directories are found
    local expected_dirs=("app1" "app2" "app3")
    for dir in "${expected_dirs[@]}"; do
        if ! grep -q "^$dir=" "$TEST_DIRLIST"; then
            echo "Directory $dir not found in dirlist"
            return 1
        fi
    done
    
    # Check that no-compose directory is not included
    if grep -q "^no-compose=" "$TEST_DIRLIST"; then
        echo "Directory without compose file incorrectly included"
        return 1
    fi
    
    return 0
}

# Check if mock commands were called correctly
check_mock_commands() {
    if [[ ! -f "$MOCK_LOG" ]]; then
        echo "Mock commands log not found"
        return 1
    fi
    
    # Check for expected command calls
    local expected_patterns=(
        "docker compose stop called"
        "docker compose start called"
        "restic backup called"
    )
    
    for pattern in "${expected_patterns[@]}"; do
        if ! grep -q "$pattern" "$MOCK_LOG"; then
            echo "Expected pattern not found in mock log: $pattern"
            return 1
        fi
    done
    
    return 0
}

# Check if backup operations were logged
check_backup_operations() {
    local backup_log="$TEST_LOG_DIR/state/backups.log"
    if [[ ! -f "$backup_log" ]]; then
        echo "Backup operations log not found"
        return 1
    fi
    
    # Check if backup was recorded
    if ! grep -q "Backup completed" "$backup_log"; then
        echo "No backup completion recorded"
        return 1
    fi
    
    return 0
}

# Check if container states were tracked
check_container_states() {
    local state_dir="$TEST_LOG_DIR/state"
    if [[ ! -d "$state_dir" ]]; then
        echo "State directory not found"
        return 1
    fi
    
    # Check for state files
    local state_files=("$state_dir"/*.state)
    if [[ ! -f "${state_files[0]}" ]]; then
        echo "No container state files found"
        return 1
    fi
    
    return 0
}

# Enable a directory for testing
enable_directory() {
    local dir_name="$1"
    if [[ -f "$TEST_DIRLIST" ]]; then
        sed -i "s/^$dir_name=false$/$dir_name=true/" "$TEST_DIRLIST"
    fi
}

#######################################
# Test Scenarios
#######################################

# Test 1: Directory Discovery
test_directory_discovery() {
    run_test "Directory Discovery" \
        "$TEST_SCRIPT --test --verbose" \
        0 \
        "check_directory_discovery"
}

# Test 2: Directory List Management
test_directory_list_management() {
    # First run to create dirlist
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    
    # Check initial state (all disabled)
    if ! grep -q "=false" "$TEST_DIRLIST"; then
        log_test_result "Directory List Management" "FAIL" "Directories not disabled by default"
        return 1
    fi
    
    # Enable one directory
    enable_directory "app1"
    
    # Check if change persists
    if ! grep -q "app1=true" "$TEST_DIRLIST"; then
        log_test_result "Directory List Management" "FAIL" "Directory enable change not persisted"
        return 1
    fi
    
    log_test_result "Directory List Management" "PASS"
}

# Test 3: Sequential Processing with Mock Commands
test_sequential_processing() {
    # Enable one directory for processing
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app1"
    
    run_test "Sequential Processing" \
        "$TEST_SCRIPT --test --verbose" \
        0 \
        "check_mock_commands"
}

# Test 4: Backup Operations
test_backup_operations() {
    # Enable directory and run backup
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app2"
    
    run_test "Backup Operations" \
        "$TEST_SCRIPT --test --verbose" \
        0 \
        "check_backup_operations"
}

# Test 5: Container State Tracking
test_container_state_tracking() {
    # Enable directory and run
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app3"
    
    run_test "Container State Tracking" \
        "$TEST_SCRIPT --test --verbose" \
        0 \
        "check_container_states"
}

# Test 6: Dry Run Mode
test_dry_run_mode() {
    # Enable directory and run in dry-run mode
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app1"
    
    run_test "Dry Run Mode" \
        "$TEST_SCRIPT --test --dry-run --verbose" \
        0
}

# Test 7: Error Handling - Docker Failure
test_docker_failure() {
    # Enable directory and simulate docker failure
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app1"
    
    run_test "Docker Failure Handling" \
        "DOCKER_FAIL_MODE=true $TEST_SCRIPT --test --verbose" \
        4  # EXIT_DOCKER_ERROR
}

# Test 8: Error Handling - Restic Failure
test_restic_failure() {
    # Enable directory and simulate restic failure
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app1"
    
    run_test "Restic Failure Handling" \
        "RESTIC_FAIL_MODE=true $TEST_SCRIPT --test --verbose" \
        3  # EXIT_BACKUP_ERROR
}

# Test 9: Multiple Directory Processing
test_multiple_directories() {
    # Enable multiple directories
    "$TEST_SCRIPT" --test >/dev/null 2>&1 || true
    enable_directory "app1"
    enable_directory "app2"
    enable_directory "app3"
    
    run_test "Multiple Directory Processing" \
        "$TEST_SCRIPT --test --verbose" \
        0 \
        "check_mock_commands"
}

# Test 10: Configuration Validation
test_configuration_validation() {
    # Test with missing config file
    run_test "Configuration Validation (Missing Config)" \
        "TEST_CONFIG=/nonexistent/config $TEST_SCRIPT --test" \
        1  # EXIT_CONFIG_ERROR
}

#######################################
# Main Test Execution
#######################################

# Display test header
show_test_header() {
    echo -e "${CYAN}"
    echo "========================================================"
    echo "  Docker Backup Script - Comprehensive Test Suite"
    echo "========================================================"
    echo -e "${NC}"
    echo "Test Environment: $(pwd)"
    echo "Test Script: $TEST_SCRIPT"
    echo "Mock Commands: ./mock-commands.sh"
    echo ""
}

# Display test summary
show_test_summary() {
    echo ""
    echo -e "${CYAN}========================================================"
    echo "                    Test Summary"
    echo -e "========================================================${NC}"
    echo "Tests Run:    $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        echo ""
        echo "The backup script test environment is working correctly."
        echo "You can now use the test environment to:"
        echo "  - Test script modifications"
        echo "  - Verify backup logic"
        echo "  - Debug issues without Docker/restic"
    else
        echo -e "${RED}Some tests failed! ✗${NC}"
        echo ""
        echo "Check the test results log for details: $TEST_RESULTS_LOG"
    fi
    
    echo ""
    echo "Test logs available in: $TEST_LOG_DIR"
    echo "Detailed results: $TEST_RESULTS_LOG"
    echo ""
}

# Main execution
main() {
    show_test_header
    
    # Validate test environment
    if [[ ! -f "$TEST_SCRIPT" ]]; then
        echo -e "${RED}Error: Test script not found: $TEST_SCRIPT${NC}"
        exit 1
    fi
    
    if [[ ! -x "$TEST_SCRIPT" ]]; then
        echo -e "${RED}Error: Test script not executable: $TEST_SCRIPT${NC}"
        exit 1
    fi
    
    # Initialize test environment
    init_test_env
    
    # Run all tests
    echo -e "${CYAN}Running test scenarios...${NC}"
    echo ""
    
    test_directory_discovery
    test_directory_list_management
    test_sequential_processing
    test_backup_operations
    test_container_state_tracking
    test_dry_run_mode
    test_docker_failure
    test_restic_failure
    test_multiple_directories
    test_configuration_validation
    
    # Show summary
    show_test_summary
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"