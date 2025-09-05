#!/bin/bash

# Working Test Suite for Docker Backup Script
# This version avoids all hanging issues by using direct execution

set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo -e "${CYAN}========================================================"
echo "  Docker Backup Script - Working Test Suite"
echo -e "========================================================${NC}"
echo "Test Environment: $(pwd)"
echo "Test Script: ./docker-backup-test.sh"
echo "Mock Commands: ./mock-commands.sh"
echo ""

# Helper functions
log_test() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$result" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        if [[ -n "$details" ]]; then
            echo -e "${YELLOW}  Details: $details${NC}"
        fi
    fi
}

cleanup_test() {
    rm -f ./logs/*.pid ./logs/*.log 2>/dev/null || true
    rm -rf ./logs/state 2>/dev/null || true
    mkdir -p ./logs
}

enable_directory() {
    local dir_name="$1"
    if [[ -f "./dirlist" ]]; then
        sed -i "s/^$dir_name=false$/$dir_name=true/" "./dirlist"
    fi
}

disable_all_directories() {
    if [[ -f "./dirlist" ]]; then
        sed -i 's/=true$/=false/g' "./dirlist"
    fi
}

echo -e "${CYAN}=== Initializing Test Environment ===${NC}"
cleanup_test
echo "Test environment initialized"
echo ""
echo -e "${CYAN}Running test scenarios...${NC}"
echo ""

# Test 1: Directory Discovery
echo -e "${BLUE}Running test: Directory Discovery${NC}"
cleanup_test
# Remove existing dirlist to force fresh discovery
rm -f "./dirlist"
./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 0 ]] && [[ -f "./dirlist" ]] && \
   grep -q "app1=" "./dirlist" && \
   grep -q "app2=" "./dirlist" && \
   grep -q "app3=" "./dirlist" && \
   ! grep -q "no-compose=" "./dirlist"; then
    log_test "Directory Discovery" "PASS"
else
    log_test "Directory Discovery" "FAIL" "Exit code: $exit_code or dirlist validation failed"
fi

# Test 2: Directory List Management
echo -e "${BLUE}Running test: Directory List Management${NC}"
if grep -q "=false" "./dirlist" 2>/dev/null; then
    enable_directory "app1"
    if grep -q "app1=true" "./dirlist" 2>/dev/null; then
        log_test "Directory List Management" "PASS"
    else
        log_test "Directory List Management" "FAIL" "Directory enable failed"
    fi
else
    log_test "Directory List Management" "FAIL" "Directories not disabled by default"
fi

# Test 3: Sequential Processing
echo -e "${BLUE}Running test: Sequential Processing${NC}"
cleanup_test
disable_all_directories
enable_directory "app1"
./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_test "Sequential Processing" "PASS"
else
    log_test "Sequential Processing" "FAIL" "Exit code: $exit_code"
fi

# Test 4: Backup Operations
echo -e "${BLUE}Running test: Backup Operations${NC}"
cleanup_test
disable_all_directories
enable_directory "app2"
./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_test "Backup Operations" "PASS"
else
    log_test "Backup Operations" "FAIL" "Exit code: $exit_code"
fi

# Test 5: Container State Tracking
echo -e "${BLUE}Running test: Container State Tracking${NC}"
cleanup_test
disable_all_directories
enable_directory "app3"
./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_test "Container State Tracking" "PASS"
else
    log_test "Container State Tracking" "FAIL" "Exit code: $exit_code"
fi

# Test 6: Dry Run Mode
echo -e "${BLUE}Running test: Dry Run Mode${NC}"
cleanup_test
disable_all_directories
enable_directory "app1"
./docker-backup-test.sh --test --dry-run >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_test "Dry Run Mode" "PASS"
else
    log_test "Dry Run Mode" "FAIL" "Exit code: $exit_code"
fi

# Test 7: Docker Failure Handling
echo -e "${BLUE}Running test: Docker Failure Handling${NC}"
cleanup_test
disable_all_directories
enable_directory "app1"
DOCKER_FAIL_MODE=true ./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 4 ]]; then
    log_test "Docker Failure Handling" "PASS"
else
    log_test "Docker Failure Handling" "FAIL" "Expected exit code 4, got $exit_code"
fi

# Test 8: Restic Failure Handling
echo -e "${BLUE}Running test: Restic Failure Handling${NC}"
cleanup_test
disable_all_directories
enable_directory "app1"
RESTIC_FAIL_MODE=true ./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 3 ]]; then
    log_test "Restic Failure Handling" "PASS"
else
    log_test "Restic Failure Handling" "FAIL" "Expected exit code 3, got $exit_code"
fi

# Test 9: Multiple Directory Processing
echo -e "${BLUE}Running test: Multiple Directory Processing${NC}"
cleanup_test
disable_all_directories
enable_directory "app1"
enable_directory "app2"
enable_directory "app3"
./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log_test "Multiple Directory Processing" "PASS"
else
    log_test "Multiple Directory Processing" "FAIL" "Exit code: $exit_code"
fi

# Test 10: Configuration Validation
echo -e "${BLUE}Running test: Configuration Validation${NC}"
cleanup_test
TEST_CONFIG=/nonexistent/config ./docker-backup-test.sh --test >/dev/null 2>&1
exit_code=$?

if [[ $exit_code -eq 1 ]]; then
    log_test "Configuration Validation" "PASS"
else
    log_test "Configuration Validation" "FAIL" "Expected exit code 1, got $exit_code"
fi

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
    echo ""
    echo "Example usage:"
    echo "  ./docker-backup-test.sh --test --verbose    # Run with verbose output"
    echo "  ./docker-backup-test.sh --test --dry-run    # Run in dry-run mode"
    echo ""
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    echo ""
    echo "Check the test logs for details:"
    echo "  - Main log: ./logs/docker_backup_test.log"
    echo "  - Mock commands: ./logs/mock-commands.log"
    echo ""
    exit 1
fi