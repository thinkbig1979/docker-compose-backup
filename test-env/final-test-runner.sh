#!/bin/bash

# Final Test Runner for Docker Backup Script
# Direct execution approach to avoid all hanging issues

set -eo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo -e "${CYAN}========================================================"
echo "  Docker Backup Script - Final Test Suite"
echo -e "========================================================${NC}"
echo ""

# Helper functions
run_single_test() {
    local test_name="$1"
    local expected_exit_code="${2:-0}"
    shift 2
    local test_command=("$@")
    
    echo -e "${BLUE}Running test: $test_name${NC}"
    
    # Clean up
    rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
    rm -rf "./logs/state" 2>/dev/null || true
    
    # Run test directly
    local actual_exit_code=0
    "${test_command[@]}" >/tmp/test_output.log 2>&1 || actual_exit_code=$?
    
    ((TESTS_RUN++))
    
    if [[ $actual_exit_code -eq $expected_exit_code ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: $test_name (exit code $actual_exit_code, expected $expected_exit_code)"
        return 1
    fi
}

enable_directory() {
    local dir_name="$1"
    if [[ -f "./dirlist" ]]; then
        sed -i "s/^$dir_name=false$/$dir_name=true/" "./dirlist"
    fi
}

check_dirlist() {
    [[ -f "./dirlist" ]] && \
    grep -q "app1=" "./dirlist" && \
    grep -q "app2=" "./dirlist" && \
    grep -q "app3=" "./dirlist" && \
    ! grep -q "no-compose=" "./dirlist"
}

# Initialize
mkdir -p "./logs"

# Test 1: Directory Discovery
run_single_test "Directory Discovery" 0 ./docker-backup-test.sh --test
if ! check_dirlist; then
    echo -e "${RED}✗ FAIL${NC}: Directory Discovery (dirlist check failed)"
    ((TESTS_FAILED++))
    ((TESTS_PASSED--))
fi

# Test 2: Directory List Management
if grep -q "=false" "./dirlist" 2>/dev/null; then
    enable_directory "app1"
    if grep -q "app1=true" "./dirlist" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: Directory List Management"
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: Directory List Management (enable failed)"
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
    fi
else
    echo -e "${RED}✗ FAIL${NC}: Directory List Management (not disabled by default)"
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
fi

# Test 3: Sequential Processing
enable_directory "app1"
run_single_test "Sequential Processing" 0 ./docker-backup-test.sh --test

# Test 4: Backup Operations
enable_directory "app2"
run_single_test "Backup Operations" 0 ./docker-backup-test.sh --test

# Test 5: Container State Tracking
enable_directory "app3"
run_single_test "Container State Tracking" 0 ./docker-backup-test.sh --test

# Test 6: Dry Run Mode
enable_directory "app1"
run_single_test "Dry Run Mode" 0 ./docker-backup-test.sh --test --dry-run

# Test 7: Docker Failure Handling
enable_directory "app1"
DOCKER_FAIL_MODE=true run_single_test "Docker Failure Handling" 4 ./docker-backup-test.sh --test

# Test 8: Restic Failure Handling
enable_directory "app1"
RESTIC_FAIL_MODE=true run_single_test "Restic Failure Handling" 3 ./docker-backup-test.sh --test

# Test 9: Multiple Directory Processing
enable_directory "app1"
enable_directory "app2"
enable_directory "app3"
run_single_test "Multiple Directory Processing" 0 ./docker-backup-test.sh --test

# Test 10: Configuration Validation
TEST_CONFIG=/nonexistent/config run_single_test "Configuration Validation" 1 ./docker-backup-test.sh --test

# Summary
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
    echo ""
    echo "Test logs available in: ./logs"
    echo "Mock command logs: ./logs/mock-commands.log"
    echo "Latest test output: /tmp/test_output.log"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    echo ""
    echo "Check the test logs for details: ./logs"
    echo "Latest test output: /tmp/test_output.log"
    exit 1
fi