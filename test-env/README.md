# Docker Backup Script Test Environment

This test environment provides comprehensive testing capabilities for the Docker backup script without requiring actual Docker or restic installations. It uses mock commands and simulated operations to verify the script's logic and behavior.

## Overview

The test environment consists of:

- **Mock directory structure** with sample Docker compose applications
- **Mock commands** that simulate Docker and restic operations
- **Test-enabled script** that can run in test mode
- **Comprehensive test suite** with automated verification
- **Detailed logging and verification** mechanisms

## Directory Structure

```
test-env/
├── docker-stacks/          # Mock backup directory
│   ├── app1/
│   │   └── docker-compose.yml
│   ├── app2/
│   │   └── docker-compose.yml
│   ├── app3/
│   │   └── compose.yml
│   └── no-compose/         # Directory without compose file
├── backup-repo/            # Mock restic repository
├── logs/                   # Test logs and state files
├── test-backup.conf        # Test configuration
├── mock-commands.sh        # Mock Docker/restic commands
├── docker-backup-test.sh   # Test-enabled backup script
├── run-tests.sh           # Comprehensive test runner
└── README.md              # This file
```

## Quick Start

### 1. Run the Complete Test Suite

```bash
# Run all automated tests
./test-env/run-tests.sh
```

This will execute 10 comprehensive test scenarios and provide a detailed report.

### 2. Manual Testing

```bash
# Run the test script manually
./test-env/docker-backup-test.sh --test --verbose

# Run in dry-run mode
./test-env/docker-backup-test.sh --test --dry-run --verbose

# Test error scenarios
DOCKER_FAIL_MODE=true ./test-env/docker-backup-test.sh --test --verbose
RESTIC_FAIL_MODE=true ./test-env/docker-backup-test.sh --test --verbose
```

### 3. Interactive Testing

```bash
# 1. Run discovery phase
./test-env/docker-backup-test.sh --test --verbose

# 2. Edit the generated dirlist to enable directories
nano test-env/dirlist

# 3. Run backup phase
./test-env/docker-backup-test.sh --test --verbose
```

## Test Components

### Mock Commands (`mock-commands.sh`)

Provides realistic simulations of:

- **Docker commands**: `docker compose stop/start`
- **Restic commands**: `restic backup/snapshots`
- **State tracking**: Container states and backup records
- **Configurable failures**: Simulate error conditions
- **Timing simulation**: Realistic command execution delays

#### Environment Variables for Mock Commands

- `DOCKER_FAIL_MODE=true`: Simulate Docker command failures
- `RESTIC_FAIL_MODE=true`: Simulate restic command failures
- `DOCKER_DELAY=N`: Set Docker command delay (seconds, default: 1)
- `RESTIC_DELAY=N`: Set restic command delay (seconds, default: 2)

### Test Script (`docker-backup-test.sh`)

Enhanced version of the main script with:

- **Test mode support**: `--test` flag or `TEST_MODE=true` in config
- **Mock command integration**: Automatic switching to mock commands
- **Test-specific logging**: Enhanced logging for verification
- **Validation bypassing**: Skip real Docker/restic checks in test mode

### Test Configuration (`test-backup.conf`)

Test-specific settings:

- Shorter timeouts for faster testing
- Points to test directory structure
- Mock repository configuration
- Test mode enabled by default

### Test Runner (`run-tests.sh`)

Comprehensive test suite covering:

1. **Directory Discovery**: Verify correct directories are found
2. **Directory List Management**: Test .dirlist creation and updates
3. **Sequential Processing**: Verify correct order and execution
4. **Backup Operations**: Test backup command execution
5. **Container State Tracking**: Verify stop/start state management
6. **Dry Run Mode**: Test dry-run functionality
7. **Error Handling**: Test Docker and restic failure scenarios
8. **Multiple Directories**: Test processing multiple enabled directories
9. **Configuration Validation**: Test config error handling

## Test Scenarios

### Scenario 1: Basic Functionality Test

```bash
# Run discovery and enable one directory
./test-env/docker-backup-test.sh --test
sed -i 's/app1=false/app1=true/' test-env/dirlist
./test-env/docker-backup-test.sh --test --verbose
```

**Expected Results:**
- Directory discovery finds 3 compose directories
- app1 is processed (stop → backup → start)
- Mock commands are called in correct order
- State files track container states
- Backup operation is recorded

### Scenario 2: Error Handling Test

```bash
# Test Docker failure
DOCKER_FAIL_MODE=true ./test-env/docker-backup-test.sh --test --verbose

# Test restic failure
RESTIC_FAIL_MODE=true ./test-env/docker-backup-test.sh --test --verbose
```

**Expected Results:**
- Script exits with appropriate error codes
- Error messages are logged
- Recovery attempts are made where appropriate

### Scenario 3: Multiple Directory Test

```bash
# Enable multiple directories
./test-env/docker-backup-test.sh --test
sed -i 's/=false/=true/g' test-env/dirlist
./test-env/docker-backup-test.sh --test --verbose
```

**Expected Results:**
- All enabled directories are processed sequentially
- Each directory goes through complete stop → backup → start cycle
- Progress is reported correctly

## Verification Methods

### 1. Log Analysis

```bash
# View main test log
tail -f test-env/logs/docker_backup_test.log

# View mock commands log
tail -f test-env/logs/mock-commands.log

# View test results
cat test-env/logs/test-results.log
```

### 2. State File Inspection

```bash
# Check container states
ls -la test-env/logs/state/
cat test-env/logs/state/*.state

# Check backup records
cat test-env/logs/state/backups.log
```

### 3. Directory List Verification

```bash
# Check generated dirlist
cat test-env/dirlist

# Verify directory discovery
grep -E "^(app1|app2|app3)=" test-env/dirlist
```

## Customization

### Adding New Test Applications

1. Create new directory in `test-env/docker-stacks/`
2. Add a `docker-compose.yml` or `compose.yml` file
3. Run discovery: `./test-env/docker-backup-test.sh --test`
4. New directory will appear in dirlist

### Modifying Test Behavior

Edit `test-env/test-backup.conf`:
- Change timeouts for different testing speeds
- Modify backup directory path
- Adjust test-specific settings

### Creating Custom Tests

Add new test functions to `test-env/run-tests.sh`:

```bash
# Custom test function
test_custom_scenario() {
    # Setup test conditions
    # Run test command
    # Verify results
    run_test "Custom Test" \
        "your_test_command" \
        expected_exit_code \
        "verification_function"
}
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   chmod +x test-env/*.sh
   ```

2. **Mock Commands Not Found**
   ```bash
   # Verify mock script exists and is executable
   ls -la test-env/mock-commands.sh
   ```

3. **Test Failures**
   ```bash
   # Check detailed logs
   cat test-env/logs/test-results.log
   cat test-env/logs/docker_backup_test.log
   ```

### Debug Mode

Run with maximum verbosity:

```bash
./test-env/docker-backup-test.sh --test --verbose 2>&1 | tee debug.log
```

### Clean Test Environment

```bash
# Remove all test artifacts
rm -f test-env/logs/*.log test-env/logs/*.pid test-env/dirlist
rm -rf test-env/logs/state
```

## Integration with Main Script

The test environment is designed to validate the main script's logic. After testing:

1. **Verify test results** are satisfactory
2. **Apply any fixes** to the main script
3. **Re-run tests** to confirm fixes
4. **Deploy with confidence** knowing the logic is sound

## Test Coverage

The test environment covers:

- ✅ Directory discovery and filtering
- ✅ Configuration loading and validation
- ✅ Directory list management (.dirlist)
- ✅ Sequential processing logic
- ✅ Docker command execution
- ✅ Restic backup operations
- ✅ Error handling and recovery
- ✅ State tracking and logging
- ✅ Dry-run functionality
- ✅ Signal handling and cleanup

## Limitations

- **No actual containers**: Mock commands simulate but don't test real Docker integration
- **No actual backups**: Mock restic doesn't test real backup functionality
- **Simplified timing**: Real operations may have different timing characteristics
- **Limited error scenarios**: Only common failure modes are simulated

For complete validation, supplement with integration tests using real Docker and restic in a controlled environment.