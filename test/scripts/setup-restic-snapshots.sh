#!/bin/bash
# Setup restic repository with test snapshots for snapshot management testing
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${YELLOW}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }

export RESTIC_REPOSITORY=/backup/restic-repo
export RESTIC_PASSWORD=test-password-123

info "Setting up restic repository with test snapshots..."

# Create test data directories
mkdir -p /opt/docker-stacks/test-stack-1/data
mkdir -p /opt/docker-stacks/test-stack-2/data
mkdir -p /opt/docker-stacks/test-stack-3/data

# Initialize repository if needed
if [ ! -d "$RESTIC_REPOSITORY" ] || [ ! -f "$RESTIC_REPOSITORY/config" ]; then
    info "Initializing restic repository..."
    restic init
    success "Repository initialized"
else
    success "Repository already exists"
fi

# Create multiple snapshots with different dates and tags
info "Creating test snapshots..."

# Snapshot 1: test-stack-1 (simulated older backup)
echo "Stack 1 data - version 1" > /opt/docker-stacks/test-stack-1/data/file.txt
echo "Config v1" > /opt/docker-stacks/test-stack-1/data/config.yml
restic backup --tag docker-backup --tag test-stack-1 --tag "2024-01-10" \
    --hostname testhost /opt/docker-stacks/test-stack-1
success "Created snapshot 1 (test-stack-1)"

# Snapshot 2: test-stack-2
echo "Stack 2 data - database dump" > /opt/docker-stacks/test-stack-2/data/dump.sql
echo "Logs from stack 2" > /opt/docker-stacks/test-stack-2/data/app.log
restic backup --tag docker-backup --tag test-stack-2 --tag "2024-01-11" \
    --hostname testhost /opt/docker-stacks/test-stack-2
success "Created snapshot 2 (test-stack-2)"

# Snapshot 3: test-stack-1 (newer version)
echo "Stack 1 data - version 2 (updated)" > /opt/docker-stacks/test-stack-1/data/file.txt
echo "Config v2" > /opt/docker-stacks/test-stack-1/data/config.yml
echo "New file added" > /opt/docker-stacks/test-stack-1/data/newfile.txt
restic backup --tag docker-backup --tag test-stack-1 --tag "2024-01-12" \
    --hostname testhost /opt/docker-stacks/test-stack-1
success "Created snapshot 3 (test-stack-1 v2)"

# Snapshot 4: test-stack-3
echo "Stack 3 important data" > /opt/docker-stacks/test-stack-3/data/important.dat
dd if=/dev/urandom of=/opt/docker-stacks/test-stack-3/data/binary.bin bs=1024 count=50 2>/dev/null
restic backup --tag docker-backup --tag test-stack-3 --tag "2024-01-13" \
    --hostname testhost /opt/docker-stacks/test-stack-3
success "Created snapshot 4 (test-stack-3)"

# Snapshot 5: test-stack-2 (updated)
echo "Stack 2 data - database dump v2" > /opt/docker-stacks/test-stack-2/data/dump.sql
echo "More logs" >> /opt/docker-stacks/test-stack-2/data/app.log
restic backup --tag docker-backup --tag test-stack-2 --tag "2024-01-14" \
    --hostname testhost /opt/docker-stacks/test-stack-2
success "Created snapshot 5 (test-stack-2 v2)"

# Verify snapshots
echo ""
info "Verifying snapshots..."
SNAPSHOT_COUNT=$(restic snapshots --json | jq length)
success "Repository has $SNAPSHOT_COUNT snapshots"

echo ""
info "Snapshot list:"
restic snapshots

echo ""
success "Restic test environment ready!"
