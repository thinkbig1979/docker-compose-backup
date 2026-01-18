#!/bin/bash
# Quick local test script - tests TUI without Docker
# Usage: ./test/quick-test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Quick TUI Test"
echo "=========================================="
echo ""

# Build
echo -e "${YELLOW}→${NC} Building backup-tui..."
go build -o bin/backup-tui ./cmd/backup-tui/
echo -e "${GREEN}✓${NC} Build successful"
echo ""

# Check if expect is available
if ! command -v expect &> /dev/null; then
    echo -e "${RED}✗${NC} 'expect' is not installed. Install it with:"
    echo "    sudo apt install expect"
    exit 1
fi

# Create a temporary test expect script
TEST_SCRIPT=$(mktemp)
cat > "$TEST_SCRIPT" << 'EXPECT_EOF'
#!/usr/bin/expect -f
set timeout 10

log_user 1

puts "\n--- Starting TUI ---"
spawn ./bin/backup-tui

# Test 1: Main menu appears
puts "\n--- Test 1: Main menu ---"
expect {
    "Main Menu" { puts "✓ Main menu displayed" }
    timeout { puts "✗ FAIL: Main menu not displayed"; exit 1 }
}

# Test 2: Navigate to Backup menu with '1'
puts "\n--- Test 2: Backup menu (shortcut) ---"
send "1"
expect {
    "Backup" { puts "✓ Backup menu displayed" }
    timeout { puts "✗ FAIL: Backup menu not displayed"; exit 1 }
}

# Test 3: ESC returns to main
puts "\n--- Test 3: ESC to return ---"
send "\033"
expect {
    "Main Menu" { puts "✓ Returned to main menu" }
    timeout { puts "✗ FAIL: Could not return"; exit 1 }
}

# Test 4: Navigate to Sync menu with '2'
puts "\n--- Test 4: Sync menu (shortcut) ---"
send "2"
expect {
    -re "Sync|Cloud" { puts "✓ Sync menu displayed" }
    timeout { puts "✗ FAIL: Sync menu not displayed"; exit 1 }
}

# Test 5: Press Enter on first item (Quick Sync)
puts "\n--- Test 5: Enter activates item ---"
send "\r"
expect {
    -re "Sync|sync|Cloud|cloud|Remote|remote|error|Error|config|Config" {
        puts "✓ Enter triggered action"
    }
    timeout { puts "✗ FAIL: Enter did nothing"; exit 1 }
}

# Wait a moment
sleep 1

# Test 6: ESC to go back
puts "\n--- Test 6: ESC from output ---"
send "\033"
sleep 1

# Test 7: Quit with 'q'
puts "\n--- Test 7: Quit ---"
send "q"
expect {
    eof { puts "✓ Application exited" }
    timeout { puts "✗ FAIL: Could not quit"; exit 1 }
}

puts "\n=========================================="
puts "  All TUI tests passed!"
puts "==========================================\n"
EXPECT_EOF

chmod +x "$TEST_SCRIPT"

# Run the test
echo -e "${YELLOW}→${NC} Running TUI tests..."
echo ""

if $TEST_SCRIPT; then
    echo -e "${GREEN}All tests passed!${NC}"
    rm "$TEST_SCRIPT"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    rm "$TEST_SCRIPT"
    exit 1
fi
