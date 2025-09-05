#!/bin/bash

# Reproduce the exact issue from docker-backup.sh
echo "=== Testing the newline issue ==="

# Simulate empty docker compose ps output
ps_output=""
running_containers="$(echo "$ps_output" | grep -c . || echo "0")"

echo "ps_output: '$ps_output'"
echo "running_containers: '$running_containers'"
echo "running_containers (hex): $(echo -n "$running_containers" | xxd -p)"
echo "Length: ${#running_containers}"

# Test the problematic conditional
echo "=== Testing the conditional that fails ==="
echo "Attempting: [[ \"$running_containers\" -gt 0 ]]"

if [[ "$running_containers" -gt 0 ]]; then
    echo "Conditional passed"
else
    echo "Conditional failed or errored"
fi