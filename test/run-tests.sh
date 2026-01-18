#!/bin/bash
# Run the test suite
# Usage: ./test/run-tests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Building backup-tui..."
go build -o bin/backup-tui ./cmd/backup-tui/

echo ""
echo "Starting test environment..."
cd "$SCRIPT_DIR"

# Clean up any previous test runs
docker compose -f docker-compose.test.yml down -v 2>/dev/null || true

# Build and run tests
docker compose -f docker-compose.test.yml build
docker compose -f docker-compose.test.yml up --abort-on-container-exit --exit-code-from test-runner

# Get exit code
EXIT_CODE=$?

# Show logs location
echo ""
echo "Test logs available at: $SCRIPT_DIR/output/test-results.log"

# Clean up (optional - comment out to inspect containers)
# docker compose -f docker-compose.test.yml down -v

exit $EXIT_CODE
