#!/bin/bash

# Simplified test runner to bypass framework issues
set -eo pipefail

# Test configuration
readonly TEST_SCRIPT="./docker-backup-test.sh"
readonly TEST_DIRLIST="./dirlist"
readonly TEST_LOG_DIR="./logs"

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
echo "  Docker Backup Script - Simplified Test Suite"
echo -e "========================================================${NC}"
echo ""

# Helper functions
run_simple_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    echo -e "${BLUE}Running test: $test_name${NC}"
    
    # Clean up
    rm -f "$TEST_LOG_DIR"/*.log "$TEST_LOG_DIR"/*.pid 2>/dev/null || true
    rm -rf "$TEST_LOG_DIR/state" 2>/dev/null || true
    
    # Run test
    local actual_exit_code=0
    if ! timeout 30 bash -c "$test_command" >/dev/null 2>&1; then
        actual_exit_code=$?
    fi
    
    ((TESTS_RUN++))
    
    if [[ $actual_exit_code -eq 124 ]]; then
        echo -e "${RED}✗ FAIL${NC}: $test_name (timed out)"
        ((TESTS_FAILED++))
        return 1
    elif [[ $actual_exit_code -ne $expected_exit_code ]]; then
        echo -e "${RED}✗ FAIL${NC}: $test_name (exit code $actual_exit_code, expected $expected_exit_code)"
        ((TESTS_FAILED++))
        return 1
    else
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    fi
}

check_directory_discovery() {
    if [[ ! -f "$TEST_DIRLIST" ]]; then
        echo "Directory list file not created"
        return 1
    fi
    
    local expected_dirs=("app1" "app2" "app3")
    for dir in "${expected_dirs[@]}"; do
        if ! grep -q "^$dir=" "$TEST_DIRLIST"; then
            echo "Directory $dir not found in dirlist"
            return 1
        fi
    done
    
    if grep -q "^no-compose=" "$TEST_DIRLIST"; then
        echo "Directory without compose file incorrectly included"
        return 1
    fi
    
    return 0
}

enable_directory() {
    local dir_name="$1"
    if [[ -f "$TEST_DIRLIST" ]]; then
        sed -i "s/^$dir_name=false$/$dir_name=true/" "$TEST_DIRLIST"
    fi
}

# Initialize
mkdir -p "$TEST_LOG_DIR"

# Test 1: Directory Discovery
run_simple_test "Directory Discovery" "$TEST_SCRIPT --test --verbose" 0
if ! check_directory_discovery >/dev/null 2>&1; then
    echo -e "${RED}✗ FAIL${NC}: Directory Discovery (check function failed)"
    ((TESTS_FAILED++))
    ((TESTS_PASSED--))
fi

# Test 2: Directory List Management
"$TEST_SCRIPT" --test >/dev/null 2>&1 || true
if grep -q "=false" "$TEST_DIRLIST"; then
    enable_directory "app1"
    if grep -q "app1=true" "$TEST_DIRLIST"; then
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
run_simple_test "Sequential Processing" "$TEST_SCRIPT --test --verbose" 0

# Test 4: Dry Run Mode
enable_directory "app1"
run_simple_test "Dry Run Mode" "$TEST_SCRIPT --test --dry-run --verbose" 0

# Test 5: Docker Failure Handling
enable_directory "app1"
run_simple_test "Docker Failure Handling" "DOCKER_FAIL_MODE=true $TEST_SCRIPT --test --verbose" 4

# Test 6: Restic Failure Handling
enable_directory "app1"
run_simple_test "Restic Failure Handling" "RESTIC_FAIL_MODE=true $TEST_SCRIPT --test --verbose" 3

# Test 7: Configuration Validation
run_simple_test "Configuration Validation" "TEST_CONFIG=/nonexistent/config $TEST_SCRIPT --test" 1

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
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    exit 1
fi