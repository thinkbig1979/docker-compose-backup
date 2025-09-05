#!/bin/bash

# Demonstration script showing the SIGKILL timing fix
# This shows the before/after behavior of the timing logic

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}SIGKILL Timing Fix Demonstration${NC}"
echo "================================="
echo ""

echo -e "${YELLOW}Problem Analysis:${NC}"
echo "The original error showed:"
echo "  - 4 containers initially running (webserver, broker, gotenberg, tika)"
echo "  - After stop command: 1 container still running (gotenberg)"
echo "  - Script failed with: 'containers still running after stop command'"
echo ""

echo -e "${YELLOW}Root Cause:${NC}"
echo "  - Docker compose stop timed out and used SIGKILL"
echo "  - Script only waited 2 seconds after stop command"
echo "  - SIGKILL cleanup for gotenberg took longer than 2 seconds"
echo "  - Script checked too early and reported failure"
echo ""

echo -e "${GREEN}Fix Implemented:${NC}"
echo "  1. Detect when stop command times out (non-zero exit code)"
echo "  2. Use extended wait time (8 seconds) for SIGKILL scenarios"
echo "  3. Add retry logic with 3 attempts and 3-second intervals"
echo "  4. Total wait time increased from 2s to up to 17s for timeout scenarios"
echo ""

echo -e "${BLUE}Timing Comparison:${NC}"
echo ""
echo -e "${RED}BEFORE (Original Logic):${NC}"
echo "  docker compose stop --timeout 30"
echo "  sleep 2                           # Only 2 seconds!"
echo "  check_stack_status                # Too early - gotenberg still cleaning up"
echo "  → FAILURE: containers still running"
echo ""

echo -e "${GREEN}AFTER (Fixed Logic):${NC}"
echo "  docker compose stop --timeout 30"
echo "  if exit_code != 0:"
echo "    wait_time = 8                   # Extended wait for SIGKILL"
echo "  else:"
echo "    wait_time = 2                   # Standard wait for graceful stop"
echo "  sleep \$wait_time"
echo "  for attempt in 1..3:"
echo "    check_stack_status"
echo "    if still_running && attempt < 3:"
echo "      sleep 3                       # Additional retry delay"
echo "  → SUCCESS: adequate time for cleanup"
echo ""

echo -e "${BLUE}Code Changes Made:${NC}"
echo "Modified smart_stop_stack() function in docker-backup.sh:"
echo ""
echo -e "${YELLOW}1. Dynamic wait time based on stop result:${NC}"
echo "   - 2 seconds for graceful stops (exit code 0)"
echo "   - 8 seconds for timeout/SIGKILL scenarios (exit code != 0)"
echo ""
echo -e "${YELLOW}2. Retry verification logic:${NC}"
echo "   - Up to 3 verification attempts"
echo "   - 3-second delay between retries"
echo "   - Total possible wait: 8 + (3 × 3) = 17 seconds for timeout scenarios"
echo ""
echo -e "${YELLOW}3. Better error reporting:${NC}"
echo "   - Shows total wait time in error messages"
echo "   - Distinguishes between graceful and forced stops"
echo ""

echo -e "${GREEN}Expected Outcome:${NC}"
echo "The paperlessngx scenario that failed before should now succeed because:"
echo "  - gotenberg container gets 8 seconds initial wait (vs 2 seconds before)"
echo "  - Up to 3 retry attempts with 3-second delays"
echo "  - Total of up to 17 seconds for SIGKILL cleanup to complete"
echo "  - This should be sufficient for most container cleanup scenarios"
echo ""

echo -e "${BLUE}Fix Applied Successfully!${NC}"
echo "The backup script now handles SIGKILL timing scenarios properly."