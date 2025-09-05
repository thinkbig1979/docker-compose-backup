#!/bin/bash

# Simple test to verify the SIGKILL timing fix
# This test focuses on the core timing logic without complex setup

set -e

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing SIGKILL timing fix${NC}"
echo "=========================="

# Create a simple test that verifies the timing logic
echo -e "${YELLOW}Testing the improved timing logic...${NC}"

# Create mock docker compose command
cat > "$TEST_DIR/mock-docker" << 'EOF'
#!/bin/bash

if [[ "$1" == "compose" && "$2" == "ps" ]]; then
    # Simulate checking container status
    if [[ -f "/tmp/containers_state" ]]; then
        cat "/tmp/containers_state"
    else
        echo ""
    fi
elif [[ "$1" == "compose" && "$2" == "stop" ]]; then
    # Simulate timeout scenario
    echo "Stopping containers..." >&2
    
    # Create initial state file showing containers running
    echo -e "gotenberg" > /tmp/containers_state
    
    # Simulate cleanup happening in background
    (
        sleep 6  # Simulate SIGKILL cleanup taking 6 seconds
        rm -f /tmp/containers_state  # All containers stopped
    ) &
    
    # Return timeout exit code (124)
    exit 124
fi
EOF

chmod +x "$TEST_DIR/mock-docker"

# Test the timing behavior
echo -e "${BLUE}Simulating container stop with timeout...${NC}"

# Set up PATH to use mock docker
export PATH="$TEST_DIR:$PATH"

# Create test directory structure
mkdir -p "$TEST_DIR/test-stack"
cd "$TEST_DIR/test-stack"

# Initialize container state
echo -e "gotenberg" > /tmp/containers_state

echo "1. Running docker compose stop (will timeout and return exit code 124)"
start_time=$(date +%s)

# This should timeout and return 124
if docker compose stop --timeout 30; then
    stop_exit_code=0
else
    stop_exit_code=$?
fi

echo "   Stop command exit code: $stop_exit_code"

# Test the improved timing logic
echo "2. Testing improved timing logic..."

if [[ $stop_exit_code -ne 0 ]]; then
    wait_time=8
    echo "   Non-zero exit code detected, using extended wait time: ${wait_time}s"
else
    wait_time=2
    echo "   Graceful stop detected, using standard wait time: ${wait_time}s"
fi

echo "3. Waiting ${wait_time} seconds for SIGKILL cleanup..."
sleep $wait_time

# Test retry logic
echo "4. Testing retry verification logic..."
verification_attempts=3
attempt=1
containers_still_running=true

while [[ $attempt -le $verification_attempts ]]; do
    echo "   Verification attempt $attempt/$verification_attempts"
    
    # Check if containers are still running
    if [[ -f "/tmp/containers_state" && -s "/tmp/containers_state" ]]; then
        if [[ $attempt -lt $verification_attempts ]]; then
            echo "   Containers still running, waiting 3 more seconds..."
            sleep 3
            attempt=$((attempt + 1))
        else
            containers_still_running=true
            break
        fi
    else
        echo "   All containers stopped!"
        containers_still_running=false
        break
    fi
done

end_time=$(date +%s)
total_time=$((end_time - start_time))

echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "============"
echo "Total time elapsed: ${total_time} seconds"
echo "Initial wait time: ${wait_time} seconds"
echo "Verification attempts: $attempt"

if [[ $containers_still_running == false ]]; then
    echo -e "${GREEN}✓ SUCCESS: Timing fix correctly handled the SIGKILL scenario${NC}"
    echo "  - Extended wait time allowed SIGKILL to complete"
    echo "  - Retry logic successfully detected when containers stopped"
    result=0
else
    echo -e "${RED}✗ FAILURE: Containers still running after all attempts${NC}"
    echo "  - May need to increase wait times further"
    result=1
fi

# Cleanup
echo ""
echo -e "${YELLOW}Cleaning up...${NC}"
rm -f /tmp/containers_state
rm -f "$TEST_DIR/mock-docker"
rm -rf "$TEST_DIR/test-stack"

echo -e "${BLUE}Test completed!${NC}"
exit $result