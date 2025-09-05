#!/bin/bash

# Ultimate Test Runner for Docker Backup Script
# Sequential execution without complex functions

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo -e "${CYAN}========================================================"
echo "  Docker Backup Script - Ultimate Test Suite"
echo -e "========================================================${NC}"
echo ""

# Initialize
mkdir -p "./logs"

# Test 1: Directory Discovery
echo -e "${BLUE}Running test: Directory Discovery${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true

./docker-backup-test.sh --test > /tmp/test1.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 0 ]] && [[ -f "./dirlist" ]] && grep -q "app1=" "./dirlist" && grep -q "app2=" "./dirlist" && grep -q "app3=" "./dirlist" && ! grep -q "no-compose=" "./dirlist"; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Directory Discovery"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Directory Discovery"
fi

# Test 2: Directory List Management
echo -e "${BLUE}Running test: Directory List Management${NC}"
((TESTS_RUN++))

if grep -q "=false" "./dirlist" 2>/dev/null; then
    sed -i "s/^app1=false$/app1=true/" "./dirlist"
    if grep -q "app1=true" "./dirlist" 2>/dev/null; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: Directory List Management"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: Directory List Management (enable failed)"
    fi
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Directory List Management (not disabled by default)"
fi

# Test 3: Sequential Processing
echo -e "${BLUE}Running test: Sequential Processing${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app1=false$/app1=true/" "./dirlist" 2>/dev/null || true

./docker-backup-test.sh --test > /tmp/test3.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 0 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Sequential Processing"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Sequential Processing"
fi

# Test 4: Backup Operations
echo -e "${BLUE}Running test: Backup Operations${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app2=false$/app2=true/" "./dirlist" 2>/dev/null || true

./docker-backup-test.sh --test > /tmp/test4.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 0 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Backup Operations"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Backup Operations"
fi

# Test 5: Container State Tracking
echo -e "${BLUE}Running test: Container State Tracking${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app3=false$/app3=true/" "./dirlist" 2>/dev/null || true

./docker-backup-test.sh --test > /tmp/test5.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 0 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Container State Tracking"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Container State Tracking"
fi

# Test 6: Dry Run Mode
echo -e "${BLUE}Running test: Dry Run Mode${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app1=false$/app1=true/" "./dirlist" 2>/dev/null || true

./docker-backup-test.sh --test --dry-run > /tmp/test6.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 0 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Dry Run Mode"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Dry Run Mode"
fi

# Test 7: Docker Failure Handling
echo -e "${BLUE}Running test: Docker Failure Handling${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app1=false$/app1=true/" "./dirlist" 2>/dev/null || true

DOCKER_FAIL_MODE=true ./docker-backup-test.sh --test > /tmp/test7.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 4 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Docker Failure Handling"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Docker Failure Handling (exit code $exit_code, expected 4)"
fi

# Test 8: Restic Failure Handling
echo -e "${BLUE}Running test: Restic Failure Handling${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app1=false$/app1=true/" "./dirlist" 2>/dev/null || true

RESTIC_FAIL_MODE=true ./docker-backup-test.sh --test > /tmp/test8.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 3 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Restic Failure Handling"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Restic Failure Handling (exit code $exit_code, expected 3)"
fi

# Test 9: Multiple Directory Processing
echo -e "${BLUE}Running test: Multiple Directory Processing${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true
sed -i "s/^app1=false$/app1=true/" "./dirlist" 2>/dev/null || true
sed -i "s/^app2=false$/app2=true/" "./dirlist" 2>/dev/null || true
sed -i "s/^app3=false$/app3=true/" "./dirlist" 2>/dev/null || true

./docker-backup-test.sh --test > /tmp/test9.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 0 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Multiple Directory Processing"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Multiple Directory Processing"
fi

# Test 10: Configuration Validation
echo -e "${BLUE}Running test: Configuration Validation${NC}"
rm -f "./logs"/*.log "./logs"/*.pid 2>/dev/null || true
rm -rf "./logs/state" 2>/dev/null || true

TEST_CONFIG=/nonexistent/config ./docker-backup-test.sh --test > /tmp/test10.log 2>&1
exit_code=$?
((TESTS_RUN++))

if [[ $exit_code -eq 1 ]]; then
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Configuration Validation"
else
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Configuration Validation (exit code $exit_code, expected 1)"
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
    echo "Individual test outputs: /tmp/test*.log"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    echo ""
    echo "Check the test logs for details: ./logs"
    echo "Individual test outputs: /tmp/test*.log"
    exit 1
fi