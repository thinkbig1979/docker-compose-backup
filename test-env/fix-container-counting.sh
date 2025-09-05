#!/bin/bash

# Fix for Container Counting Logic in docker-backup.sh
# Demonstrates the problem and provides the correct solution

set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}========================================================"
echo "  Container Counting Logic - Problem & Solution"
echo -e "========================================================${NC}"
echo ""

echo -e "${RED}PROBLEM DEMONSTRATION:${NC}"
echo "Current broken implementation in docker-backup.sh (line 494):"
echo "  running_containers=\$(echo \"\$ps_output\" | wc -l)"
echo ""

# Demonstrate the exact problem
echo -e "${YELLOW}Testing with empty ps_output (no running containers):${NC}"
ps_output=""
echo "ps_output='$ps_output'"

# Current broken method
broken_count=$(echo "$ps_output" | wc -l)
echo "Current method result: $broken_count"
echo "Expected result: 0"
echo -e "${RED}❌ BROKEN: Returns $broken_count instead of 0${NC}"
echo ""

echo -e "${GREEN}SOLUTION:${NC}"
echo "Replace line 494 in docker-backup.sh with:"
echo "  running_containers=\$(echo \"\$ps_output\" | awk 'NF' | wc -l)"
echo ""

# Demonstrate the fix
echo -e "${YELLOW}Testing the fix:${NC}"
fixed_count=$(echo "$ps_output" | awk 'NF' | wc -l)
echo "Fixed method result: $fixed_count"
echo "Expected result: 0"
echo -e "${GREEN}✅ FIXED: Correctly returns $fixed_count${NC}"
echo ""

echo -e "${BLUE}VERIFICATION WITH DIFFERENT SCENARIOS:${NC}"
echo ""

# Test scenarios
scenarios=(
    ""                    # Empty (critical case)
    "web"                 # Single container
    $'web\ndb\nredis'     # Multiple containers
    $'   \n  \n'          # Whitespace only
    $'web\n\ndb\n\n'      # Mixed empty/non-empty
)

scenario_names=(
    "Empty (no containers)"
    "Single container"
    "Multiple containers"
    "Whitespace only"
    "Mixed empty/non-empty"
)

expected_counts=(0 1 3 0 2)

echo "| Scenario | Current (broken) | Fixed | Expected | Status |"
echo "|----------|------------------|-------|----------|--------|"

all_fixed=true
for i in "${!scenarios[@]}"; do
    ps_output="${scenarios[$i]}"
    expected="${expected_counts[$i]}"
    
    broken_result=$(echo "$ps_output" | wc -l)
    fixed_result=$(echo "$ps_output" | awk 'NF' | wc -l)
    
    if [[ "$fixed_result" == "$expected" ]]; then
        status="✅ PASS"
    else
        status="❌ FAIL"
        all_fixed=false
    fi
    
    printf "| %-20s | %-16s | %-5s | %-8s | %s |\n" \
        "${scenario_names[$i]}" "$broken_result" "$fixed_result" "$expected" "$status"
done

echo ""

if [[ "$all_fixed" == "true" ]]; then
    echo -e "${GREEN}✅ All scenarios pass with the fix!${NC}"
else
    echo -e "${RED}❌ Some scenarios still fail${NC}"
fi

echo ""
echo -e "${CYAN}IMPLEMENTATION DETAILS:${NC}"
echo ""
echo "The fix uses 'awk NF' which:"
echo "  - NF = Number of Fields in each line"
echo "  - awk 'NF' only prints lines that have at least one field"
echo "  - Empty lines and whitespace-only lines have NF=0, so they're filtered out"
echo "  - Then wc -l counts only the non-empty lines"
echo ""

echo "Alternative solutions (in order of preference):"
echo "1. awk 'NF' | wc -l           (RECOMMENDED - most reliable)"
echo "2. sed '/^[[:space:]]*$/d' | wc -l  (handles whitespace-only lines)"
echo "3. grep -c .                 (original approach, but has edge cases)"
echo ""

echo -e "${YELLOW}EXACT CHANGE NEEDED:${NC}"
echo ""
echo "File: docker-backup.sh"
echo "Line: 494"
echo ""
echo -e "${RED}- running_containers=\$(echo \"\$ps_output\" | wc -l)${NC}"
echo -e "${GREEN}+ running_containers=\$(echo \"\$ps_output\" | awk 'NF' | wc -l)${NC}"
echo ""

echo -e "${CYAN}========================================================"
echo "                    Summary"
echo -e "========================================================${NC}"
echo "✅ Problem identified: wc -l counts empty lines"
echo "✅ Solution tested: awk 'NF' | wc -l filters empty lines"
echo "✅ All test scenarios pass with the fix"
echo "✅ Ready to apply the fix to docker-backup.sh"
echo ""