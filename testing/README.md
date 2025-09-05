# Backup System Test Suite

Comprehensive test suite for the 3-stage Docker backup system, providing unit, integration, and end-to-end testing with Docker-based test environments.

## Overview

This test suite validates the complete backup system workflow:
1. **Docker Backup** - Backing up Docker stacks using restic
2. **Cloud Sync** - Syncing backups to cloud storage using rclone  
3. **TUI Management** - Text user interface for backup operations
4. **Directory Management** - Selective backup using directory lists

## Test Structure

```
testing/
├── unit/                   # Unit tests for individual components
│   ├── test_docker_backup.bats
│   └── test_backup_tui.bats
├── integration/           # Integration tests for component interactions
│   ├── test_backup_workflow.bats
│   └── test_rclone_integration.bats
├── e2e/                   # End-to-end system tests
│   └── test_complete_system.bats
├── docker/                # Docker test environment
│   ├── docker-compose.test.yml
│   └── test-runner.Dockerfile
├── fixtures/              # Test data and configurations
│   ├── docker-stacks/     # Sample Docker compose files
│   ├── configs/           # Test configurations
│   └── test-data/         # Sample test files
├── scripts/               # Test utilities and runners
│   ├── run-tests.sh       # Main test runner
│   ├── test-helpers.sh    # Common test functions
│   └── setup-test-env.sh  # Environment setup
└── results/               # Test results and reports
```

## Quick Start

### 1. Setup Test Environment

Install test dependencies:
```bash
cd testing/scripts
./setup-test-env.sh --all
```

Or install specific tools:
```bash
./setup-test-env.sh --bats --docker --rclone --restic
```

Check current installation status:
```bash
./setup-test-env.sh --check
```

### 2. Run Tests

Run all tests locally:
```bash
./run-tests.sh
```

Run tests in Docker environment (isolated and reproducible):
```bash
./run-tests.sh --docker
```

Run specific test suites:
```bash
./run-tests.sh unit           # Unit tests only
./run-tests.sh integration   # Integration tests only
./run-tests.sh e2e           # End-to-end tests only
```

Run with verbose output:
```bash
./run-tests.sh --verbose --docker
```

## Test Environments

### Local Testing
- Uses system-installed tools (docker, restic, rclone, bats)
- Faster execution
- May be affected by local environment

### Docker Testing  
- Isolated test environment using Docker containers
- Consistent across different systems
- Includes mock services (S3, restic server)
- Network simulation for failure testing

### Test Services

The Docker environment provides:
- **backup-source**: Docker-in-Docker for testing Docker stacks
- **restic-server**: REST server for backup destination testing
- **minio**: S3-compatible storage for cloud sync testing
- **network-chaos**: Network failure simulation
- **resource-limited**: Resource-constrained testing

## Test Scenarios

### Unit Tests
- Script argument parsing and validation
- Configuration file handling
- Error handling for missing dependencies
- Mock-based testing for external tools
- Function-level testing

### Integration Tests
- Complete backup workflow with real Docker stacks
- Restic repository operations
- rclone sync operations
- Directory list filtering
- Verification and validation processes

### End-to-End Tests
- Full 3-stage backup system
- TUI interaction simulation
- Error recovery and graceful failures
- Performance and monitoring integration
- Cross-platform compatibility

## Test Fixtures

### Docker Stacks
- **test-app**: Multi-service stack (nginx, postgres, redis)
- **minimal-app**: Simple single-service stack
- **broken-stack**: Invalid configuration for error testing

### Configurations
- **backup.conf.test**: Test backup configuration
- **rclone.conf.test**: Test cloud storage configuration
- Sample directory lists and test data

## Test Helpers

Common utilities in `scripts/test-helpers.sh`:
- Mock function creation (docker, restic, rclone, dialog)
- Test data generation
- Service availability checks
- Resource monitoring
- Performance measurement

## Running Individual Tests

### Using BATS directly
```bash
bats testing/unit/test_docker_backup.bats
```

### Using Docker environment
```bash
docker-compose -f testing/docker/docker-compose.test.yml run --rm backup-test-runner \
  bats testing/unit/test_docker_backup.bats
```

### Debug mode
```bash
BATS_DEBUG=1 ./run-tests.sh unit --verbose
```

## Test Results

Test results are stored in `testing/results/`:
- `*-results.tap`: TAP format test results
- `*-report.txt`: Human-readable test reports
- `overall-report.txt`: Summary of all test suites
- Performance metrics (when enabled)

## Continuous Integration

The test suite is designed for CI/CD integration:

```yaml
# Example GitHub Actions
- name: Setup Test Environment
  run: ./testing/scripts/setup-test-env.sh --all

- name: Run Tests
  run: ./testing/scripts/run-tests.sh --docker --verbose

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: testing/results/
```

## Troubleshooting

### Common Issues

1. **Docker permission denied**
   ```bash
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

2. **BATS not found**
   ```bash
   ./setup-test-env.sh --bats
   ```

3. **Test services not starting**
   ```bash
   docker-compose -f testing/docker/docker-compose.test.yml logs
   ```

4. **Tests failing in Docker**
   ```bash
   docker-compose -f testing/docker/docker-compose.test.yml exec backup-test-runner bash
   # Debug interactively
   ```

### Debug Commands

Check test environment:
```bash
./run-tests.sh --check
```

Verify Docker test services:
```bash
docker-compose -f testing/docker/docker-compose.test.yml ps
```

Access test runner container:
```bash
docker-compose -f testing/docker/docker-compose.test.yml exec backup-test-runner bash
```

## Performance Testing

Enable resource monitoring:
```bash
MONITOR_RESOURCES=true ./run-tests.sh
```

Run performance tests:
```bash
./run-tests.sh --pattern "*performance*"
```

## Contributing

### Adding New Tests

1. **Unit tests**: Add to `testing/unit/`
2. **Integration tests**: Add to `testing/integration/`
3. **E2E tests**: Add to `testing/e2e/`

### Test Naming Convention
- Files: `test_component_name.bats`
- Functions: `@test "description of what is being tested"`

### Test Structure
```bash
@test "Component: specific functionality" {
    # Setup
    setup_test_environment
    
    # Execute
    run command_under_test
    
    # Verify
    assert_success
    assert_output --partial "expected output"
}
```

## Security Considerations

- Test configurations use mock credentials
- Isolated Docker network for tests
- Temporary directories cleaned up automatically
- No production data used in tests

## License

Same as parent project - see main project README for license information.