#!/bin/bash

set -euo pipefail

# Test configuration
readonly TEST_SCRIPT="./docker-backup-test.sh"
readonly TEST_DIRLIST="./dirlist"

echo "=== Debug Single Test ==="
echo "Running: $TEST_SCRIPT --test --verbose"

# Clean up
rm -f ./logs/*.log ./logs/*.pid 2>/dev/null || true
rm -rf ./logs/state 2>/dev/null || true

# Run the test
echo "Starting test..."
if timeout 30 bash -c "$TEST_SCRIPT --test --verbose" >/dev/null 2>&1; then
    echo "Test command completed successfully"
    exit_code=0
else
    exit_code=$?
    echo "Test command failed with exit code: $exit_code"
fi

# Check directory discovery
echo "Checking directory discovery..."
if [[ ! -f "$TEST_DIRLIST" ]]; then
    echo "FAIL: Directory list file not created"
    exit 1
fi

# Check if all expected directories are found
expected_dirs=("app1" "app2" "app3")
for dir in "${expected_dirs[@]}"; do
    if ! grep -q "^$dir=" "$TEST_DIRLIST"; then
        echo "FAIL: Directory $dir not found in dirlist"
        exit 1
    fi
done

# Check that no-compose directory is not included
if grep -q "^no-compose=" "$TEST_DIRLIST"; then
    echo "FAIL: Directory without compose file incorrectly included"
    exit 1
fi

echo "SUCCESS: Directory discovery test passed"
exit 0