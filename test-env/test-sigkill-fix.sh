#!/bin/bash

# Test script to verify the SIGKILL timing fix
# This script simulates the scenario where containers take time to stop after SIGKILL

set -e

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")"
BACKUP_SCRIPT="$SCRIPT_DIR/docker-backup.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing SIGKILL timing fix for docker-backup.sh${NC}"
echo "=============================================="

# Create test environment
echo -e "${YELLOW}Setting up test environment...${NC}"

# Create mock docker compose command that simulates timeout behavior
cat > "$TEST_DIR/mock-docker-compose" << 'EOF'
#!/bin/bash

# Mock docker compose command for testing SIGKILL timing

if [[ "$1" == "ps" ]]; then
    # Simulate container status checking
    if [[ -f "/tmp/test_containers_running" ]]; then
        # Read the current container count from file
        cat "/tmp/test_containers_running"
    else
        echo ""  # No containers running
    fi
elif [[ "$1" == "stop" ]]; then
    # Simulate stop command with timeout behavior
    echo "Stopping containers..." >&2
    
    # Simulate initial container state (4 containers)
    echo -e "webserver\nbroker\ngotenberg\ntika" > /tmp/test_containers_running
    
    # Simulate timeout scenario (exit code 124 for timeout)
    sleep 1
    
    # After "timeout", simulate gradual container stopping
    # First, 3 containers stop quickly
    echo -e "gotenberg" > /tmp/test_containers_running
    
    # Simulate the problematic scenario: gotenberg takes longer to stop
    # This will be handled by the improved timing logic
    (
        sleep 5  # Simulate SIGKILL taking 5 seconds to fully clean up
        rm -f /tmp/test_containers_running  # All containers finally stopped
    ) &
    
    # Return timeout exit code to trigger the enhanced timing logic
    exit 124
fi
EOF

chmod +x "$TEST_DIR/mock-docker-compose"

# Create test backup configuration
cat > "$TEST_DIR/test-backup-sigkill.conf" << EOF
BACKUP_DIR="$TEST_DIR/docker-stacks"
RESTIC_REPOSITORY="$TEST_DIR/backup-repo"
RESTIC_PASSWORD="test123"
DOCKER_TIMEOUT=30
BACKUP_TIMEOUT=300
EOF

# Create test dirlist
echo "paperlessngx=true" > "$TEST_DIR/test-dirlist-sigkill"

# Create test stack directory
mkdir -p "$TEST_DIR/docker-stacks/paperlessngx"
cat > "$TEST_DIR/docker-stacks/paperlessngx/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  webserver:
    image: nginx:alpine
  broker:
    image: redis:alpine
  gotenberg:
    image: gotenberg/gotenberg:7
  tika:
    image: apache/tika:latest
EOF

# Initialize restic repository
mkdir -p "$TEST_DIR/backup-repo"
export RESTIC_REPOSITORY="$TEST_DIR/backup-repo"
export RESTIC_PASSWORD="test123"

echo -e "${YELLOW}Running test with SIGKILL timing fix...${NC}"

# Temporarily modify PATH to use our mock docker compose
export PATH="$TEST_DIR:$PATH"

# Set up initial container state
echo -e "webserver\nbroker\ngotenberg\ntika" > /tmp/test_containers_running

# Run the backup script with our test configuration
cd "$TEST_DIR/docker-stacks/paperlessngx"

# Test the smart_stop_stack function directly by sourcing the script
# and calling the function with debug output
export BACKUP_CONFIG="$TEST_DIR/test-backup-sigkill.conf"
export VERBOSE=true

echo -e "${BLUE}Simulating the problematic scenario...${NC}"
echo "- Initial state: 4 containers running (webserver, broker, gotenberg, tika)"
echo "- Stop command will timeout and use SIGKILL"
echo "- gotenberg container will take 5 seconds to fully clean up after SIGKILL"
echo "- Testing if the improved timing logic handles this correctly"
echo ""

# Source the backup script to get access to functions
source "$BACKUP_SCRIPT"

# Initialize logging
init_logging

# Load configuration
load_configuration

# Test the improved stop logic
echo -e "${YELLOW}Testing smart_stop_stack function...${NC}"

# Set up the stack state
STACK_INITIAL_STATE["paperlessngx"]="running"

# Call the function that was fixed
if smart_stop_stack "paperlessngx" "$TEST_DIR/docker-stacks/paperlessngx"; then
    echo -e "${GREEN}✓ SUCCESS: smart_stop_stack completed successfully${NC}"
    echo "The improved timing logic correctly handled the SIGKILL scenario"
else
    echo -e "${RED}✗ FAILURE: smart_stop_stack failed${NC}"
    echo "The timing fix may need further adjustment"
fi

# Cleanup
echo -e "${YELLOW}Cleaning up test environment...${NC}"
rm -f /tmp/test_containers_running
rm -f "$TEST_DIR/mock-docker-compose"
rm -rf "$TEST_DIR/docker-stacks/paperlessngx"
rm -f "$TEST_DIR/test-backup-sigkill.conf"
rm -f "$TEST_DIR/test-dirlist-sigkill"

echo -e "${BLUE}Test completed!${NC}"