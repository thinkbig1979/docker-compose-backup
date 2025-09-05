#!/bin/bash

# Comprehensive Container Counting Logic Tests
# Tests to reproduce and fix the wc -l vs grep -c issue

set +e  # Allow failures for testing

# Colors for output
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
echo "  Container Counting Logic - Comprehensive Tests"
echo -e "========================================================${NC}"
echo "Testing the wc -l vs grep -c issue in docker-backup.sh"
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

# Test function for different counting methods
test_counting_method() {
    local method_name="$1"
    local ps_output="$2"
    local expected_count="$3"
    local count_command="$4"
    
    local actual_count
    actual_count=$(eval "$count_command")
    
    echo -e "${BLUE}Testing: $method_name${NC}"
    echo "  Input: '$ps_output'"
    echo "  Expected: $expected_count"
    echo "  Actual: $actual_count"
    echo "  Command: $count_command"
    
    if [[ "$actual_count" == "$expected_count" ]]; then
        log_test "$method_name" "PASS"
    else
        log_test "$method_name" "FAIL" "Expected $expected_count, got $actual_count"
    fi
    echo ""
}

echo -e "${CYAN}=== Testing Different Scenarios ===${NC}"
echo ""

# Scenario 1: Empty ps_output (most critical case)
echo -e "${YELLOW}Scenario 1: Empty ps_output (no running containers)${NC}"
ps_output=""

# Current broken method (wc -l)
test_counting_method "wc -l (BROKEN)" "$ps_output" "0" 'echo "$ps_output" | wc -l'

# Original method (grep -c with fallback)
test_counting_method "grep -c . with fallback" "$ps_output" "0" 'echo "$ps_output" | grep -c . || echo "0"'

# Alternative methods
test_counting_method "awk method" "$ps_output" "0" 'echo "$ps_output" | awk "NF" | wc -l'
test_counting_method "sed method" "$ps_output" "0" 'echo "$ps_output" | sed "/^$/d" | wc -l'
test_counting_method "bash array method" "$ps_output" "0" 'readarray -t lines <<< "$ps_output"; count=0; for line in "${lines[@]}"; do [[ -n "$line" ]] && ((count++)); done; echo "$count"'

# Scenario 2: Single container
echo -e "${YELLOW}Scenario 2: Single container running${NC}"
ps_output="web"

test_counting_method "wc -l (single)" "$ps_output" "1" 'echo "$ps_output" | wc -l'
test_counting_method "grep -c . (single)" "$ps_output" "1" 'echo "$ps_output" | grep -c . || echo "0"'
test_counting_method "awk method (single)" "$ps_output" "1" 'echo "$ps_output" | awk "NF" | wc -l'
test_counting_method "sed method (single)" "$ps_output" "1" 'echo "$ps_output" | sed "/^$/d" | wc -l'

# Scenario 3: Multiple containers
echo -e "${YELLOW}Scenario 3: Multiple containers running${NC}"
ps_output="web
db
redis"

test_counting_method "wc -l (multiple)" "$ps_output" "3" 'echo "$ps_output" | wc -l'
test_counting_method "grep -c . (multiple)" "$ps_output" "3" 'echo "$ps_output" | grep -c . || echo "0"'
test_counting_method "awk method (multiple)" "$ps_output" "3" 'echo "$ps_output" | awk "NF" | wc -l'
test_counting_method "sed method (multiple)" "$ps_output" "3" 'echo "$ps_output" | sed "/^$/d" | wc -l'

# Scenario 4: Whitespace only
echo -e "${YELLOW}Scenario 4: Whitespace only${NC}"
ps_output="   
  
"

test_counting_method "wc -l (whitespace)" "$ps_output" "0" 'echo "$ps_output" | wc -l'
test_counting_method "grep -c . (whitespace)" "$ps_output" "0" 'echo "$ps_output" | grep -c . || echo "0"'
test_counting_method "awk method (whitespace)" "$ps_output" "0" 'echo "$ps_output" | awk "NF" | wc -l'
test_counting_method "sed method (whitespace)" "$ps_output" "0" 'echo "$ps_output" | sed "/^$/d" | wc -l'

# Scenario 5: Mixed empty and non-empty lines
echo -e "${YELLOW}Scenario 5: Mixed empty and non-empty lines${NC}"
ps_output="web

db

"

test_counting_method "wc -l (mixed)" "$ps_output" "2" 'echo "$ps_output" | wc -l'
test_counting_method "grep -c . (mixed)" "$ps_output" "2" 'echo "$ps_output" | grep -c . || echo "0"'
test_counting_method "awk method (mixed)" "$ps_output" "2" 'echo "$ps_output" | awk "NF" | wc -l'
test_counting_method "sed method (mixed)" "$ps_output" "2" 'echo "$ps_output" | sed "/^$/d" | wc -l'

echo -e "${CYAN}=== Testing Edge Cases ===${NC}"
echo ""

# Edge case 1: Single newline
echo -e "${YELLOW}Edge Case 1: Single newline character${NC}"
ps_output=$'\n'

test_counting_method "wc -l (single newline)" "$ps_output" "0" 'echo "$ps_output" | wc -l'
test_counting_method "grep -c . (single newline)" "$ps_output" "0" 'echo "$ps_output" | grep -c . || echo "0"'

# Edge case 2: Multiple newlines
echo -e "${YELLOW}Edge Case 2: Multiple newlines${NC}"
ps_output=$'\n\n\n'

test_counting_method "wc -l (multiple newlines)" "$ps_output" "0" 'echo "$ps_output" | wc -l'
test_counting_method "grep -c . (multiple newlines)" "$ps_output" "0" 'echo "$ps_output" | grep -c . || echo "0"'

echo -e "${CYAN}=== Recommended Solutions ===${NC}"
echo ""

# Test the most robust solutions
echo -e "${YELLOW}Testing Recommended Solutions:${NC}"
echo ""

# Solution 1: awk NF (most readable and reliable)
test_solution() {
    local solution_name="$1"
    local test_cases=("" "web" $'web\ndb\nredis' $'   \n  \n' $'web\n\ndb\n\n')
    local expected_counts=(0 1 3 0 2)
    local command="$2"
    
    echo -e "${BLUE}Testing Solution: $solution_name${NC}"
    echo "Command: $command"
    
    local all_passed=true
    for i in "${!test_cases[@]}"; do
        local ps_output="${test_cases[$i]}"
        local expected="${expected_counts[$i]}"
        local actual
        actual=$(eval "$command")
        
        if [[ "$actual" == "$expected" ]]; then
            echo -e "  ${GREEN}✓${NC} Case $((i+1)): Expected $expected, got $actual"
        else
            echo -e "  ${RED}✗${NC} Case $((i+1)): Expected $expected, got $actual"
            all_passed=false
        fi
    done
    
    if [[ "$all_passed" == "true" ]]; then
        log_test "$solution_name" "PASS"
    else
        log_test "$solution_name" "FAIL" "One or more test cases failed"
    fi
    echo ""
}

# Test recommended solutions
test_solution "awk NF method" 'echo "$ps_output" | awk "NF" | wc -l'
test_solution "sed empty line removal" 'echo "$ps_output" | sed "/^$/d" | wc -l'
test_solution "grep -c with proper fallback" 'echo "$ps_output" | grep -c . || echo "0"'

# Test a more robust bash-only solution
test_solution "bash array with validation" '
if [[ -z "$ps_output" ]]; then
    echo "0"
else
    readarray -t lines <<< "$ps_output"
    count=0
    for line in "${lines[@]}"; do
        [[ -n "$line" && "$line" =~ [^[:space:]] ]] && ((count++))
    done
    echo "$count"
fi'

echo -e "${CYAN}=== Performance Comparison ===${NC}"
echo ""

# Simple performance test
echo "Testing performance of different methods (1000 iterations each):"
echo ""

performance_test() {
    local method_name="$1"
    local command="$2"
    local test_data="$3"
    
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    for ((i=0; i<1000; i++)); do
        ps_output="$test_data"
        eval "$command" >/dev/null
    done
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    echo "  $method_name: ${duration}ms"
}

test_data="web
db
redis"

performance_test "wc -l (broken)" 'echo "$ps_output" | wc -l'
performance_test "awk NF" 'echo "$ps_output" | awk "NF" | wc -l'
performance_test "sed method" 'echo "$ps_output" | sed "/^$/d" | wc -l'
performance_test "grep -c" 'echo "$ps_output" | grep -c . || echo "0"'

echo ""
echo -e "${CYAN}=== Summary and Recommendations ===${NC}"
echo ""

echo "PROBLEM ANALYSIS:"
echo "- The current wc -l method counts ALL lines, including empty ones"
echo "- When ps_output is empty, 'echo \"\" | wc -l' returns 1, not 0"
echo "- This causes the script to think containers are running when they're not"
echo ""

echo "RECOMMENDED SOLUTIONS (in order of preference):"
echo ""
echo "1. awk NF method (RECOMMENDED):"
echo "   running_containers=\$(echo \"\$ps_output\" | awk \"NF\" | wc -l)"
echo "   - Most readable and reliable"
echo "   - awk NF only prints lines with non-empty fields"
echo "   - Good performance"
echo ""

echo "2. sed method:"
echo "   running_containers=\$(echo \"\$ps_output\" | sed \"/^\$/d\" | wc -l)"
echo "   - Removes empty lines before counting"
echo "   - Very reliable"
echo ""

echo "3. grep -c with proper error handling:"
echo "   running_containers=\$(echo \"\$ps_output\" | grep -c . || echo \"0\")"
echo "   - Original approach but with proper fallback"
echo "   - Handles the pipeline failure case"
echo ""

# Summary
echo ""
echo -e "${CYAN}========================================================"
echo "                    Test Summary"
echo -e "========================================================${NC}"
echo "Tests Run:    $TESTS_RUN"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests completed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests revealed issues! ✗${NC}"
    exit 1
fi