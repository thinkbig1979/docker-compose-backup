#!/bin/bash
# Validation script for backup system test suite
# Ensures all test files and fixtures are properly configured

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTING_DIR="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT="$(dirname "${TESTING_DIR}")"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

#######################################
# Print colored output
#######################################
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

print_info() {
    print_color "${BLUE}" "INFO: $1"
}

print_success() {
    print_color "${GREEN}" "✓ $1"
}

print_warning() {
    print_color "${YELLOW}" "⚠ WARNING: $1"
    ((VALIDATION_WARNINGS++))
}

print_error() {
    print_color "${RED}" "✗ ERROR: $1"
    ((VALIDATION_ERRORS++))
}

#######################################
# Check file exists and is executable
#######################################
check_executable() {
    local file="$1"
    local description="$2"
    
    if [[ -f "${file}" ]]; then
        if [[ -x "${file}" ]]; then
            print_success "${description} exists and is executable"
        else
            print_error "${description} exists but is not executable"
        fi
    else
        print_error "${description} not found: ${file}"
    fi
}

#######################################
# Check file exists
#######################################
check_file() {
    local file="$1"
    local description="$2"
    
    if [[ -f "${file}" ]]; then
        print_success "${description} exists"
    else
        print_error "${description} not found: ${file}"
    fi
}

#######################################
# Check directory exists
#######################################
check_directory() {
    local dir="$1"
    local description="$2"
    
    if [[ -d "${dir}" ]]; then
        print_success "${description} directory exists"
    else
        print_error "${description} directory not found: ${dir}"
    fi
}

#######################################
# Validate test structure
#######################################
validate_test_structure() {
    print_info "Validating test directory structure..."
    
    # Check main directories
    check_directory "${TESTING_DIR}/unit" "Unit tests"
    check_directory "${TESTING_DIR}/integration" "Integration tests"
    check_directory "${TESTING_DIR}/e2e" "End-to-end tests"
    check_directory "${TESTING_DIR}/docker" "Docker configurations"
    check_directory "${TESTING_DIR}/fixtures" "Test fixtures"
    check_directory "${TESTING_DIR}/scripts" "Test scripts"
    
    # Create results directory if missing
    if [[ ! -d "${TESTING_DIR}/results" ]]; then
        mkdir -p "${TESTING_DIR}/results"
        print_warning "Created missing results directory"
    else
        print_success "Results directory exists"
    fi
}

#######################################
# Validate test scripts
#######################################
validate_test_scripts() {
    print_info "Validating test scripts..."
    
    check_executable "${TESTING_DIR}/scripts/run-tests.sh" "Main test runner"
    check_executable "${TESTING_DIR}/scripts/setup-test-env.sh" "Environment setup script"
    check_executable "${TESTING_DIR}/scripts/performance-test.sh" "Performance test script"
    check_file "${TESTING_DIR}/scripts/test-helpers.sh" "Test helper functions"
    check_file "${TESTING_DIR}/scripts/validate-test-suite.sh" "This validation script"
}

#######################################
# Validate test files
#######################################
validate_test_files() {
    print_info "Validating test files..."
    
    # Unit tests
    check_file "${TESTING_DIR}/unit/test_docker_backup.bats" "Docker backup unit tests"
    check_file "${TESTING_DIR}/unit/test_backup_tui.bats" "Backup TUI unit tests"
    check_file "${TESTING_DIR}/unit/test_manage_dirlist.bats" "Directory management unit tests"
    
    # Integration tests
    check_file "${TESTING_DIR}/integration/test_backup_workflow.bats" "Backup workflow integration tests"
    check_file "${TESTING_DIR}/integration/test_rclone_integration.bats" "rclone integration tests"
    
    # E2E tests
    check_file "${TESTING_DIR}/e2e/test_complete_system.bats" "Complete system E2E tests"
}

#######################################
# Validate Docker configurations
#######################################
validate_docker_configs() {
    print_info "Validating Docker configurations..."
    
    check_file "${TESTING_DIR}/docker/docker-compose.test.yml" "Docker Compose test configuration"
    check_file "${TESTING_DIR}/docker/test-runner.Dockerfile" "Test runner Dockerfile"
    
    # Validate Docker Compose syntax
    if command -v docker-compose >/dev/null 2>&1; then
        if docker-compose -f "${TESTING_DIR}/docker/docker-compose.test.yml" config >/dev/null 2>&1; then
            print_success "Docker Compose configuration is valid"
        else
            print_error "Docker Compose configuration has syntax errors"
        fi
    else
        print_warning "docker-compose not available to validate configuration"
    fi
}

#######################################
# Validate test fixtures
#######################################
validate_test_fixtures() {
    print_info "Validating test fixtures..."
    
    # Docker stack fixtures
    check_directory "${TESTING_DIR}/fixtures/docker-stacks" "Docker stack fixtures"
    check_file "${TESTING_DIR}/fixtures/docker-stacks/test-app/docker-compose.yml" "Test app Docker compose"
    check_file "${TESTING_DIR}/fixtures/docker-stacks/minimal-app/docker-compose.yml" "Minimal app Docker compose"
    
    # Configuration fixtures
    check_directory "${TESTING_DIR}/fixtures/configs" "Configuration fixtures"
    check_file "${TESTING_DIR}/fixtures/configs/backup.conf.test" "Test backup configuration"
    check_file "${TESTING_DIR}/fixtures/configs/rclone.conf.test" "Test rclone configuration"
    
    # Test data fixtures
    check_directory "${TESTING_DIR}/fixtures/test-data" "Test data fixtures"
    check_file "${TESTING_DIR}/fixtures/test-data/sample-file.txt" "Sample test file"
}

#######################################
# Validate main project scripts
#######################################
validate_main_scripts() {
    print_info "Validating main project scripts..."
    
    check_executable "${PROJECT_ROOT}/backup-tui.sh" "Main TUI script"
    check_executable "${PROJECT_ROOT}/docker-backup.sh" "Docker backup script"
    check_executable "${PROJECT_ROOT}/manage-dirlist.sh" "Directory list management script"
    check_file "${PROJECT_ROOT}/rclone_backup.sh" "rclone backup script"
    check_file "${PROJECT_ROOT}/rclone_restore.sh" "rclone restore script"
    
    # Check configuration templates
    check_file "${PROJECT_ROOT}/backup.conf" "Main backup configuration"
    check_file "${PROJECT_ROOT}/backup.conf.template" "Backup configuration template"
}

#######################################
# Validate BATS test syntax
#######################################
validate_bats_syntax() {
    print_info "Validating BATS test syntax..."
    
    if ! command -v bats >/dev/null 2>&1; then
        print_warning "BATS not installed, skipping syntax validation"
        return 0
    fi
    
    # Find all .bats files
    local bats_files
    mapfile -t bats_files < <(find "${TESTING_DIR}" -name "*.bats" -type f)
    
    local syntax_errors=0
    for bats_file in "${bats_files[@]}"; do
        if bats --pretty --verbose-run "${bats_file}" --count >/dev/null 2>&1; then
            print_success "BATS syntax OK: $(basename "${bats_file}")"
        else
            print_error "BATS syntax error: $(basename "${bats_file}")"
            ((syntax_errors++))
        fi
    done
    
    if [[ ${syntax_errors} -eq 0 ]]; then
        print_success "All BATS files have valid syntax"
    else
        print_error "${syntax_errors} BATS files have syntax errors"
    fi
}

#######################################
# Check test dependencies
#######################################
check_test_dependencies() {
    print_info "Checking test dependencies..."
    
    # Essential tools
    local tools=("bash" "docker" "docker-compose" "bats" "restic" "rclone" "dialog" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "${tool}" >/dev/null 2>&1; then
            print_success "${tool} is available"
        else
            print_warning "${tool} is not installed"
            missing_tools+=("${tool}")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Missing tools: ${missing_tools[*]}"
        print_info "Run: ./setup-test-env.sh --all to install missing dependencies"
    fi
    
    # Check Docker daemon
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            print_success "Docker daemon is running"
        else
            print_warning "Docker is installed but daemon is not accessible"
        fi
    fi
    
    # Check BATS helpers
    if [[ -n "${BATS_LIB_PATH:-}" ]] && [[ -d "${BATS_LIB_PATH}" ]]; then
        print_success "BATS helper libraries available at ${BATS_LIB_PATH}"
    else
        print_warning "BATS_LIB_PATH not set or directory not found"
        print_info "BATS helper libraries may not be available for tests"
    fi
}

#######################################
# Generate validation report
#######################################
generate_validation_report() {
    local report_file="${TESTING_DIR}/results/validation-report.txt"
    
    print_info "Generating validation report..."
    
    {
        echo "Backup System Test Suite Validation Report"
        echo "Generated: $(date)"
        echo "==========================================="
        echo
        echo "Validation Summary:"
        echo "- Errors: ${VALIDATION_ERRORS}"
        echo "- Warnings: ${VALIDATION_WARNINGS}"
        echo
        
        if [[ ${VALIDATION_ERRORS} -eq 0 ]]; then
            echo "STATUS: PASSED - Test suite is ready to use"
        else
            echo "STATUS: FAILED - Test suite has ${VALIDATION_ERRORS} errors that must be fixed"
        fi
        
        echo
        echo "Test Suite Structure:"
        echo "- Unit tests: $(find "${TESTING_DIR}/unit" -name "*.bats" 2>/dev/null | wc -l) files"
        echo "- Integration tests: $(find "${TESTING_DIR}/integration" -name "*.bats" 2>/dev/null | wc -l) files"
        echo "- E2E tests: $(find "${TESTING_DIR}/e2e" -name "*.bats" 2>/dev/null | wc -l) files"
        echo "- Docker configs: $(find "${TESTING_DIR}/docker" -name "*.yml" -o -name "Dockerfile*" 2>/dev/null | wc -l) files"
        echo "- Test fixtures: $(find "${TESTING_DIR}/fixtures" -type f 2>/dev/null | wc -l) files"
        echo "- Helper scripts: $(find "${TESTING_DIR}/scripts" -name "*.sh" 2>/dev/null | wc -l) files"
        
    } > "${report_file}"
    
    print_success "Validation report generated: ${report_file}"
}

#######################################
# Main function
#######################################
main() {
    print_info "Validating backup system test suite..."
    echo
    
    # Run all validations
    validate_test_structure
    echo
    
    validate_test_scripts
    echo
    
    validate_test_files
    echo
    
    validate_docker_configs
    echo
    
    validate_test_fixtures
    echo
    
    validate_main_scripts
    echo
    
    validate_bats_syntax
    echo
    
    check_test_dependencies
    echo
    
    # Generate report
    mkdir -p "${TESTING_DIR}/results"
    generate_validation_report
    
    # Final summary
    echo
    print_info "VALIDATION SUMMARY:"
    if [[ ${VALIDATION_ERRORS} -eq 0 ]]; then
        print_success "Test suite validation PASSED!"
        print_info "You can now run tests with: ./run-tests.sh"
        
        if [[ ${VALIDATION_WARNINGS} -gt 0 ]]; then
            print_warning "${VALIDATION_WARNINGS} warnings found - check validation report for details"
        fi
    else
        print_error "Test suite validation FAILED!"
        print_error "${VALIDATION_ERRORS} errors must be fixed before running tests"
        if [[ ${VALIDATION_WARNINGS} -gt 0 ]]; then
            print_warning "Also found ${VALIDATION_WARNINGS} warnings"
        fi
        exit 1
    fi
    
    return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi