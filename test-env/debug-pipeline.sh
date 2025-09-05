#!/bin/bash

echo "=== Testing pipeline behavior ==="

# Test the exact command from the script
ps_output=""
echo "ps_output: '$ps_output'"

# Test step by step
echo -e "\nStep 1: echo \"\$ps_output\""
echo "$ps_output" | cat -A  # Show all characters

echo -e "\nStep 2: echo \"\$ps_output\" | grep -c ."
result_grep=$(echo "$ps_output" | grep -c .)
echo "Result: '$result_grep'"
echo "Exit code: $?"

echo -e "\nStep 3: Full command with ||"
result_full="$(echo "$ps_output" | grep -c . || echo "0")"
echo "Result: '$result_full'"
echo "Result with cat -A:"
echo "$result_full" | cat -A

# Test alternative approaches
echo -e "\nAlternative 1: Using wc -l"
alt1="$(echo "$ps_output" | wc -l)"
echo "wc -l result: '$alt1'"

echo -e "\nAlternative 2: Stripping newlines"
alt2="$(echo "$ps_output" | grep -c . || echo "0")"
alt2_clean="${alt2%$'\n'}"  # Remove trailing newline
echo "Cleaned result: '$alt2_clean'"
echo "Length: ${#alt2_clean}"