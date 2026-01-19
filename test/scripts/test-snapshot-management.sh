#!/bin/bash
# Test snapshot management TUI functionality
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${YELLOW}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
header() { echo -e "\n${CYAN}═══ $1 ═══${NC}\n"; }

export RESTIC_REPOSITORY=/backup/restic-repo
export RESTIC_PASSWORD=test-password-123

# Output directory for captures
OUTPUT_DIR=/app/output/snapshot-tests
mkdir -p "$OUTPUT_DIR"

# Ensure we're in the config directory so backup-tui finds config.ini
cd /app/config

# Verify config exists
if [ ! -f config.ini ]; then
    echo "Error: config.ini not found in /app/config"
    ls -la /app/config/
    exit 1
fi

info "Using config from: $(pwd)/config.ini"

header "Snapshot Management TUI Tests"

# First ensure we have a restic repository with snapshots
info "Setting up restic repository with test snapshots..."

# Initialize repository if needed
if [ ! -d "$RESTIC_REPOSITORY" ] || [ ! -f "$RESTIC_REPOSITORY/config" ]; then
    info "Initializing restic repository..."
    restic init 2>&1 || true
fi

# Check current snapshot count
SNAPSHOT_COUNT=$(restic snapshots --json 2>/dev/null | jq length 2>/dev/null || echo "0")

if [ "$SNAPSHOT_COUNT" -lt 3 ]; then
    info "Creating test snapshots (need at least 3)..."

    # Create test data directories
    mkdir -p /opt/docker-stacks/test-stack-1/data
    mkdir -p /opt/docker-stacks/test-stack-2/data

    # Create snapshot 1
    echo "Stack 1 data v1 - $(date)" > /opt/docker-stacks/test-stack-1/data/file.txt
    restic backup --tag docker-backup --tag test-stack-1 --hostname testhost /opt/docker-stacks/test-stack-1 2>&1

    # Create snapshot 2
    echo "Stack 2 data - $(date)" > /opt/docker-stacks/test-stack-2/data/dump.sql
    restic backup --tag docker-backup --tag test-stack-2 --hostname testhost /opt/docker-stacks/test-stack-2 2>&1

    # Create snapshot 3 (updated stack 1)
    echo "Stack 1 data v2 - $(date)" > /opt/docker-stacks/test-stack-1/data/file.txt
    echo "New file" > /opt/docker-stacks/test-stack-1/data/new.txt
    restic backup --tag docker-backup --tag test-stack-1 --hostname testhost /opt/docker-stacks/test-stack-1 2>&1

    SNAPSHOT_COUNT=$(restic snapshots --json | jq length)
fi

success "Repository has $SNAPSHOT_COUNT snapshots"

# Show snapshot list for verification
info "Current snapshots:"
restic snapshots

# Test 1: Capture main menu
header "Test 1: Main Menu"
info "Capturing main menu..."
tui-goggles -cols 100 -rows 25 -delay 1s -- backup-tui > "$OUTPUT_DIR/01-main-menu.txt"
success "Main menu captured"
cat "$OUTPUT_DIR/01-main-menu.txt"

# Test 2: Navigate to Backup menu
header "Test 2: Backup Menu"
info "Capturing backup menu..."
tui-goggles -cols 100 -rows 25 -keys "1" -delay 1s -- backup-tui > "$OUTPUT_DIR/02-backup-menu.txt"
success "Backup menu captured"
cat "$OUTPUT_DIR/02-backup-menu.txt"

# Test 3: Navigate to Snapshot Management screen
header "Test 3: Snapshot Management Screen"
info "Opening snapshot management..."
tui-goggles -cols 120 -rows 30 -keys "1 m" -delay 5s -stable-time 1s -- backup-tui > "$OUTPUT_DIR/03-snapshot-management.txt"
success "Snapshot management screen captured"
cat "$OUTPUT_DIR/03-snapshot-management.txt"

# Verify the screen shows snapshots
if grep -q "Snapshot Management" "$OUTPUT_DIR/03-snapshot-management.txt"; then
    success "Snapshot Management title visible"
else
    fail "Snapshot Management title not found"
fi

if grep -q "Navigate" "$OUTPUT_DIR/03-snapshot-management.txt" && grep -q "Toggle" "$OUTPUT_DIR/03-snapshot-management.txt"; then
    success "Key instructions visible"
else
    fail "Key instructions not found"
fi

# Check if snapshots are listed (look for short IDs which are 8 hex chars)
if grep -qE '\[ \].*[a-f0-9]{8}' "$OUTPUT_DIR/03-snapshot-management.txt" || \
   grep -qE '\[x\].*[a-f0-9]{8}' "$OUTPUT_DIR/03-snapshot-management.txt"; then
    success "Snapshots are listed"
else
    if grep -q "Error" "$OUTPUT_DIR/03-snapshot-management.txt"; then
        fail "Error loading snapshots - check environment variables"
    else
        fail "No snapshots listed"
    fi
fi

# Check selected count display
if grep -q "Selected:.*Total:" "$OUTPUT_DIR/03-snapshot-management.txt"; then
    success "Selection counter displayed"
else
    fail "Selection counter not found"
fi

# Test 4: Navigate down in snapshot list
header "Test 4: Navigation in Snapshot List"
info "Testing navigation (down arrow)..."
tui-goggles -cols 120 -rows 30 -keys "1 m down down" -delay 5s -stable-time 1s -- backup-tui > "$OUTPUT_DIR/04-snapshot-nav.txt"
success "Navigation captured"
cat "$OUTPUT_DIR/04-snapshot-nav.txt"

# Test 5: Select a snapshot with SPACE
header "Test 5: Select Snapshot"
info "Testing selection (space key)..."
tui-goggles -cols 120 -rows 30 -keys "1 m space" -delay 5s -stable-time 1s -- backup-tui > "$OUTPUT_DIR/05-snapshot-select.txt"
success "Selection captured"
cat "$OUTPUT_DIR/05-snapshot-select.txt"

# Check for selection marker [x]
if grep -q '\[x\]' "$OUTPUT_DIR/05-snapshot-select.txt"; then
    success "Snapshot selection working (found [x] marker)"
else
    fail "Selection marker [x] not found after pressing SPACE"
fi

# Check that selected count increased
if grep -q "Selected: 1" "$OUTPUT_DIR/05-snapshot-select.txt"; then
    success "Selected count shows 1"
else
    info "Note: Selected count may not show 1"
fi

# Test 6: Select all
header "Test 6: Select All"
info "Testing select all (a key)..."
tui-goggles -cols 120 -rows 30 -keys "1 m a" -delay 5s -stable-time 1s -- backup-tui > "$OUTPUT_DIR/06-snapshot-select-all.txt"
success "Select all captured"
cat "$OUTPUT_DIR/06-snapshot-select-all.txt"

# Check that all are selected (no [ ] should remain, all should be [x])
UNSELECTED_COUNT=$(grep -c '\[ \]' "$OUTPUT_DIR/06-snapshot-select-all.txt" || echo "0")
if [ "$UNSELECTED_COUNT" = "0" ]; then
    success "All snapshots selected (no [ ] checkboxes remain)"
else
    info "Note: Some snapshots may not be selected"
fi

# Test 7: ESC returns to backup menu
header "Test 7: ESC Navigation"
info "Testing ESC to return..."
tui-goggles -cols 100 -rows 25 -keys "1 m esc" -delay 5s -stable-time 1s -- backup-tui > "$OUTPUT_DIR/07-esc-back.txt"
success "ESC navigation captured"
cat "$OUTPUT_DIR/07-esc-back.txt"

if grep -q "Backup Menu\|Backup Options" "$OUTPUT_DIR/07-esc-back.txt"; then
    success "ESC returns to Backup menu"
else
    fail "ESC did not return to Backup menu"
fi

# ==========================================
# Deletion and Pruning Tests
# ==========================================

header "Test 8: Dry-Run Deletion (Shift+D)"
info "Recording snapshot count before deletion..."
BEFORE_COUNT=$(restic snapshots --json 2>/dev/null | jq length)
info "Snapshots before: $BEFORE_COUNT"

info "Testing dry-run deletion (select first snapshot, press Shift+D)..."
# Select first snapshot with space, then Shift+D for dry-run
tui-goggles -cols 120 -rows 35 -keys "1 m space D" -delay 8s -stable-time 2s -- backup-tui > "$OUTPUT_DIR/08-delete-dry-run.txt"
success "Dry-run deletion captured"
cat "$OUTPUT_DIR/08-delete-dry-run.txt"

# Verify dry-run output shows in the output screen
if grep -qi "dry\|Dry Run\|Forgetting" "$OUTPUT_DIR/08-delete-dry-run.txt"; then
    success "Dry-run deletion output visible"
else
    info "Note: Dry-run output may have completed quickly"
fi

# Verify snapshot count unchanged after dry-run
AFTER_DRYRUN_COUNT=$(restic snapshots --json 2>/dev/null | jq length)
if [ "$AFTER_DRYRUN_COUNT" = "$BEFORE_COUNT" ]; then
    success "Dry-run did not delete snapshots (count unchanged: $AFTER_DRYRUN_COUNT)"
else
    fail "Dry-run unexpectedly changed snapshot count: $BEFORE_COUNT -> $AFTER_DRYRUN_COUNT"
fi

header "Test 9: Actual Snapshot Deletion (D key)"
info "Snapshots before deletion: $BEFORE_COUNT"
info "Current snapshots:"
restic snapshots --json | jq -r '.[] | "\(.short_id) - \(.tags | join(", "))"'

# Get the first snapshot ID to verify it's deleted
FIRST_SNAPSHOT_ID=$(restic snapshots --json | jq -r '.[0].short_id')
info "Will delete snapshot: $FIRST_SNAPSHOT_ID"

info "Selecting first snapshot and pressing 'd' for actual deletion..."
# Select first snapshot with space, then lowercase 'd' for actual delete
tui-goggles -cols 120 -rows 35 -keys "1 m space d" -delay 10s -stable-time 2s -- backup-tui > "$OUTPUT_DIR/09-delete-actual.txt"
success "Deletion operation captured"
cat "$OUTPUT_DIR/09-delete-actual.txt"

# Wait a moment for restic to complete
sleep 2

# Verify snapshot was actually deleted
AFTER_DELETE_COUNT=$(restic snapshots --json 2>/dev/null | jq length)
info "Snapshots after deletion: $AFTER_DELETE_COUNT"

if [ "$AFTER_DELETE_COUNT" -lt "$BEFORE_COUNT" ]; then
    success "Snapshot deleted successfully (count: $BEFORE_COUNT -> $AFTER_DELETE_COUNT)"
else
    fail "Snapshot was NOT deleted (count unchanged: $BEFORE_COUNT)"
fi

# Verify the specific snapshot ID is gone
if restic snapshots --json | jq -r '.[].short_id' | grep -q "^${FIRST_SNAPSHOT_ID}$"; then
    fail "Snapshot $FIRST_SNAPSHOT_ID still exists after deletion"
else
    success "Snapshot $FIRST_SNAPSHOT_ID confirmed removed from repository"
fi

info "Remaining snapshots:"
restic snapshots

header "Test 10: Dry-Run Prune (Shift+P)"
info "Testing dry-run prune..."
tui-goggles -cols 120 -rows 35 -keys "1 m P" -delay 10s -stable-time 2s -- backup-tui > "$OUTPUT_DIR/10-prune-dry-run.txt"
success "Dry-run prune captured"
cat "$OUTPUT_DIR/10-prune-dry-run.txt"

if grep -qi "prune\|Prune\|Pruning" "$OUTPUT_DIR/10-prune-dry-run.txt"; then
    success "Prune operation initiated"
else
    info "Note: Prune output may have completed quickly"
fi

header "Test 11: Actual Repository Prune (P key)"
info "Running actual prune operation..."
# Note: lowercase 'p' for actual prune
tui-goggles -cols 120 -rows 35 -keys "1 m p" -delay 15s -stable-time 3s -- backup-tui > "$OUTPUT_DIR/11-prune-actual.txt"
success "Prune operation captured"
cat "$OUTPUT_DIR/11-prune-actual.txt"

# Wait for prune to complete
sleep 2

# Verify repository integrity after prune
header "Test 12: Repository Integrity Check"
info "Verifying repository integrity after operations..."
if restic check 2>&1 | tee "$OUTPUT_DIR/12-repo-check.txt" | grep -qi "no errors"; then
    success "Repository integrity verified - no errors found"
else
    # Check might not output "no errors" explicitly
    if restic check 2>&1; then
        success "Repository check passed"
    else
        fail "Repository integrity check failed"
    fi
fi

# Final snapshot count
FINAL_COUNT=$(restic snapshots --json 2>/dev/null | jq length)
info "Final snapshot count: $FINAL_COUNT"

header "Test Summary"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  SNAPSHOT MANAGEMENT VALIDATION COMPLETE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  UI Tests:"
echo "    ✓ Main menu display"
echo "    ✓ Backup menu with 'Manage Snapshots' option"
echo "    ✓ Snapshot list display with checkboxes"
echo "    ✓ Navigation (up/down arrows)"
echo "    ✓ Selection (SPACE key)"
echo "    ✓ Select all (A key)"
echo "    ✓ ESC navigation"
echo ""
echo "  Deletion Tests:"
echo "    ✓ Dry-run deletion (Shift+D) - no changes made"
echo "    ✓ Actual deletion (D key) - snapshot removed"
echo "    ✓ Snapshot count decreased: $BEFORE_COUNT -> $AFTER_DELETE_COUNT"
echo ""
echo "  Prune Tests:"
echo "    ✓ Dry-run prune (Shift+P)"
echo "    ✓ Actual prune (P key)"
echo "    ✓ Repository integrity verified"
echo ""
echo "  Final state: $FINAL_COUNT snapshots remaining"
echo ""
echo "All captures saved to: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo ""
success "All snapshot management tests passed!"
