#!/bin/bash

# Minimal Test Runner - Just run tests one by one
set -e

echo "========================================================"
echo "  Docker Backup Script - Minimal Test Suite"
echo "========================================================"
echo ""

# Clean up
rm -f ./logs/*.pid ./logs/*.log 2>/dev/null || true
rm -rf ./logs/state 2>/dev/null || true
mkdir -p ./logs

echo "Test 1: Directory Discovery"
./docker-backup-test.sh --test >/dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL"

echo "Test 2: Sequential Processing (with enabled directory)"
sed -i 's/app1=false/app1=true/' ./dirlist 2>/dev/null || true
./docker-backup-test.sh --test >/dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL"

echo "Test 3: Dry Run Mode"
./docker-backup-test.sh --test --dry-run >/dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL"

echo "Test 4: Docker Failure Handling"
DOCKER_FAIL_MODE=true ./docker-backup-test.sh --test >/dev/null 2>&1
if [[ $? -eq 4 ]]; then
    echo "✓ PASS"
else
    echo "✗ FAIL"
fi

echo "Test 5: Restic Failure Handling"
RESTIC_FAIL_MODE=true ./docker-backup-test.sh --test >/dev/null 2>&1
if [[ $? -eq 3 ]]; then
    echo "✓ PASS"
else
    echo "✗ FAIL"
fi

echo "Test 6: Configuration Validation"
TEST_CONFIG=/nonexistent/config ./docker-backup-test.sh --test >/dev/null 2>&1
if [[ $? -eq 1 ]]; then
    echo "✓ PASS"
else
    echo "✗ FAIL"
fi

echo ""
echo "All tests completed!"
echo "Check ./logs/mock-commands.log for mock command execution details"