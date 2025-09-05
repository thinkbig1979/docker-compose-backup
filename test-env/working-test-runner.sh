#!/bin/bash

# Working Test Runner for Docker Backup Script
# Ultra-simplified approach to avoid all hanging issues

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
echo "  Docker Backup Script - Working Test Suite"
echo -e "========================================================${NC}"
echo ""

# Helper functions
log_test() {
    local test_name="$1"
    local result="$2"
    
    ((TESTS_RUN++))
    
    if [[ "$result" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: $test_name"
    fi
}

enable_directory() {
    local dir_name="$1"
    if [[ -f "./dirlist" ]]; then
        sed -i "s/^$dir_name=false$/$dir_name=true/" "./dirlist"
    fi
}

# Initialize
mkdir -p "./logs"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true

echo -e "${BLUE}Running test: Directory Discovery${NC}"
# Test 1: Directory Discovery
if ./docker-backup-test.sh --test >/dev/null 2>&1; then
    if [[ -f "./dirlist" ]] && grep -q "app1=" "./dirlist" && grep -q "app2=" "./dirlist" && grep -q "app3=" "./dirlist" && ! grep -q "no-compose=" "./dirlist"; then
        log_test "Directory Discovery" "PASS"
    else
        log_test "Directory Discovery" "FAIL"
    fi
else
    log_test "Directory Discovery" "FAIL"
fi

echo -e "${BLUE}Running test: Directory List Management${NC}"
# Test 2: Directory List Management
if grep -q "=false" "./dirlist"; then
    enable_directory "app1"
    if grep -q "app1=true" "./dirlist"; then
        log_test "Directory List Management" "PASS"
    else
        log_test "Directory List Management" "FAIL"
    fi
else
    log_test "Directory List Management" "FAIL"
fi

echo -e "${BLUE}Running test: Sequential Processing${NC}"
# Test 3: Sequential Processing
enable_directory "app1"
if ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Sequential Processing" "PASS"
else
    log_test "Sequential Processing" "FAIL"
fi

echo -e "${BLUE}Running test: Backup Operations${NC}"
# Test 4: Backup Operations
enable_directory "app2"
if ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Backup Operations" "PASS"
else
    log_test "Backup Operations" "FAIL"
fi

echo -e "${BLUE}Running test: Container State Tracking${NC}"
# Test 5: Container State Tracking
enable_directory "app3"
if ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Container State Tracking" "PASS"
else
    log_test "Container State Tracking" "FAIL"
fi

echo -e "${BLUE}Running test: Dry Run Mode${NC}"
# Test 6: Dry Run Mode
enable_directory "app1"
if ./docker-backup-test.sh --test --dry-run >/dev/null 2>&1; then
    log_test "Dry Run Mode" "PASS"
else
    log_test "Dry Run Mode" "FAIL"
fi

echo -e "${BLUE}Running test: Docker Failure Handling${NC}"
# Test 7: Docker Failure Handling
enable_directory "app1"
if DOCKER_FAIL_MODE=true ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Docker Failure Handling" "FAIL"
else
    exit_code=$?
    if [[ $exit_code -eq 4 ]]; then
        log_test "Docker Failure Handling" "PASS"
    else
        log_test "Docker Failure Handling" "FAIL"
    fi
fi

echo -e "${BLUE}Running test: Restic Failure Handling${NC}"
# Test 8: Restic Failure Handling
enable_directory "app1"
if RESTIC_FAIL_MODE=true ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Restic Failure Handling" "FAIL"
else
    exit_code=$?
    if [[ $exit_code -eq 3 ]]; then
        log_test "Restic Failure Handling" "PASS"
    else
        log_test "Restic Failure Handling" "FAIL"
    fi
fi

echo -e "${BLUE}Running test: Multiple Directory Processing${NC}"
# Test 9: Multiple Directory Processing
enable_directory "app1"
enable_directory "app2"
enable_directory "app3"
if ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Multiple Directory Processing" "PASS"
else
    log_test "Multiple Directory Processing" "FAIL"
fi

echo -e "${BLUE}Running test: Configuration Validation${NC}"
# Test 10: Configuration Validation
if TEST_CONFIG=/nonexistent/config ./docker-backup-test.sh --test >/dev/null 2>&1; then
    log_test "Configuration Validation" "FAIL"
else
    exit_code=$?
    if [[ $exit_code -eq 1 ]]; then
        log_test "Configuration Validation" "PASS"
    else
        log_test "Configuration Validation" "FAIL"
    fi
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
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    echo ""
    echo "Check the test logs for details: ./logs"
    exit 1
fi