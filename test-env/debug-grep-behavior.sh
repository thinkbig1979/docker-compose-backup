#!/bin/bash

echo "=== Testing grep -c behavior ==="

# Test 1: Empty string
echo "Test 1: Empty string"
ps_output=""
result1="$(echo "$ps_output" | grep -c .)"
echo "grep -c result: '$result1'"
echo "grep exit code: $?"

# Test 2: With fallback
echo -e "\nTest 2: With || echo fallback"
ps_output=""
result2="$(echo "$ps_output" | grep -c . || echo "0")"
echo "grep -c with fallback: '$result2'"
echo "Length: ${#result2}"

# Test 3: Check what happens with non-empty input
echo -e "\nTest 3: Non-empty input"
ps_output="service1"
result3="$(echo "$ps_output" | grep -c . || echo "0")"
echo "grep -c with content: '$result3'"
echo "Length: ${#result3}"