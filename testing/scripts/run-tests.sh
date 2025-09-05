#!/bin/bash
# Test runner script for backup system
# Runs all test suites with proper environment setup

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TESTING_DIR="${SCRIPT_DIR}/.."

# Test configuration
readonly DOCKER_COMPOSE_FILE="${TESTING_DIR}/docker/docker-compose.test.yml"
readonly TEST_RESULTS_DIR="${TESTING_DIR}/results"
readonly COVERAGE_DIR="${TESTING_DIR}/coverage"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false
DOCKER_MODE=false
CLEANUP_ON_EXIT=true
PARALLEL_JOBS=1
TEST_PATTERN="*"

#######################################
# Display usage information
#######################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_SUITE]

Run test suite for backup system.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --docker           Run tests in Docker environment
    -c, --no-cleanup       Don't cleanup after tests
    -j, --jobs NUM         Number of parallel test jobs (default: 1)
    -p, --pattern PATTERN  Test file pattern (default: *)
    --unit                 Run only unit tests
    --integration          Run only integration tests
    --e2e                  Run only end-to-end tests
    --all                  Run all test suites (default)

TEST_SUITE:
    unit                   Run unit tests only
    integration           Run integration tests only
    e2e                   Run end-to-end tests only
    all                   Run all test suites (default)

EXAMPLES:
    $0                      # Run all tests locally
    $0 --docker --verbose  # Run all tests in Docker with verbose output
    $0 unit                # Run only unit tests
    $0 --pattern "*backup*" # Run tests matching pattern

EOF
}

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
    print_color "${GREEN}" "SUCCESS: $1"
}

print_warning() {
    print_color "${YELLOW}" "WARNING: $1"
}

print_error() {
    print_color "${RED}" "ERROR: $1"
}

#######################################
# Setup test environment
#######################################
setup_test_environment() {
    print_info "Setting up test environment..."
    
    # Create test directories
    mkdir -p "${TEST_RESULTS_DIR}" "${COVERAGE_DIR}"
    
    # Set test environment variables
    export TEST_MODE=true
    export BATS_LIB_PATH="${BATS_LIB_PATH:-/opt/bats-helpers}"
    
    # Setup test-specific paths
    if [[ "${DOCKER_MODE}" == "true" ]]; then
        export TEST_WORKSPACE="/workspace"
    else
        export TEST_WORKSPACE="${PROJECT_ROOT}"
    fi
    
    print_success "Test environment ready"
}

#######################################
# Check test dependencies
#######################################
check_dependencies() {
    print_info "Checking test dependencies..."
    
    local missing_deps=()
    
    if [[ "${DOCKER_MODE}" == "true" ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            missing_deps+=("docker")
        fi
        if ! command -v docker-compose >/dev/null 2>&1; then
            missing_deps+=("docker-compose")
        fi
    else
        if ! command -v bats >/dev/null 2>&1; then
            missing_deps+=("bats")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Install missing dependencies or use --docker mode"
        exit 1
    fi
    
    print_success "All dependencies available"
}

#######################################
# Start Docker test environment
#######################################
start_docker_environment() {
    print_info "Starting Docker test environment..."
    
    if [[ ! -f "${DOCKER_COMPOSE_FILE}" ]]; then
        print_error "Docker compose file not found: ${DOCKER_COMPOSE_FILE}"
        exit 1
    fi
    
    # Build test runner image
    docker-compose -f "${DOCKER_COMPOSE_FILE}" build backup-test-runner
    
    # Start test infrastructure
    docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d backup-source restic-server minio
    
    # Wait for services to be ready
    print_info "Waiting for test services to be ready..."
    sleep 30
    
    # Verify services are healthy
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" ps | grep -q "Up (healthy)"; then
        print_warning "Some services may not be fully ready"
        docker-compose -f "${DOCKER_COMPOSE_FILE}" ps
    fi
    
    print_success "Docker test environment ready"
}

#######################################
# Stop Docker test environment
#######################################
stop_docker_environment() {
    if [[ "${CLEANUP_ON_EXIT}" == "true" && -f "${DOCKER_COMPOSE_FILE}" ]]; then
        print_info "Stopping Docker test environment..."
        docker-compose -f "${DOCKER_COMPOSE_FILE}" down -v --remove-orphans
        print_success "Docker test environment stopped"
    fi
}

#######################################
# Run test suite
#######################################
run_test_suite() {
    local suite="$1"
    local test_dir="${TESTING_DIR}/${suite}"
    local results_file="${TEST_RESULTS_DIR}/${suite}-results.tap"
    
    if [[ ! -d "${test_dir}" ]]; then
        print_warning "Test suite directory not found: ${test_dir}"
        return 1
    fi
    
    print_info "Running ${suite} tests..."
    
    local test_files
    mapfile -t test_files < <(find "${test_dir}" -name "${TEST_PATTERN}.bats" -type f)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        print_warning "No test files found in ${test_dir} matching pattern ${TEST_PATTERN}"
        return 0
    fi
    
    local bats_options=()
    [[ "${VERBOSE}" == "true" ]] && bats_options+=("--verbose-run")
    bats_options+=("--tap")
    bats_options+=("--jobs" "${PARALLEL_JOBS}")
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    if [[ "${DOCKER_MODE}" == "true" ]]; then
        run_tests_in_docker "${suite}" "${bats_options[@]}" "${test_files[@]}"
    else
        run_tests_locally "${results_file}" "${bats_options[@]}" "${test_files[@]}"
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    print_success "${suite} tests completed in ${duration}s"
    
    # Generate test report
    if [[ -f "${results_file}" ]]; then
        generate_test_report "${suite}" "${results_file}"
    fi
}

#######################################
# Run tests locally
#######################################
run_tests_locally() {
    local results_file="$1"
    shift
    local bats_options=("$@")
    
    if bats "${bats_options[@]}" > "${results_file}" 2>&1; then
        print_success "Tests passed"
        [[ "${VERBOSE}" == "true" ]] && cat "${results_file}"
        return 0
    else
        print_error "Tests failed"
        cat "${results_file}"
        return 1
    fi
}

#######################################
# Run tests in Docker
#######################################
run_tests_in_docker() {
    local suite="$1"
    shift
    local bats_options=("$@")
    
    local docker_cmd=(
        "docker-compose" "-f" "${DOCKER_COMPOSE_FILE}" 
        "exec" "-T" "backup-test-runner"
        "bats" "${bats_options[@]}"
    )
    
    if "${docker_cmd[@]}"; then
        print_success "Docker tests passed"
        return 0
    else
        print_error "Docker tests failed"
        return 1
    fi
}

#######################################
# Generate test report
#######################################
generate_test_report() {
    local suite="$1"
    local results_file="$2"
    local report_file="${TEST_RESULTS_DIR}/${suite}-report.txt"
    
    print_info "Generating test report for ${suite}..."
    
    {
        echo "Test Report: ${suite}"
        echo "Generated: $(date)"
        echo "Results File: ${results_file}"
        echo "==============================================="
        echo
        
        if grep -q "not ok" "${results_file}"; then
            echo "FAILED TESTS:"
            grep "not ok" "${results_file}" || true
            echo
        fi
        
        local total_tests passed_tests failed_tests
        total_tests=$(grep -c "^ok\|^not ok" "${results_file}" || echo "0")
        passed_tests=$(grep -c "^ok" "${results_file}" || echo "0")
        failed_tests=$(grep -c "^not ok" "${results_file}" || echo "0")
        
        echo "SUMMARY:"
        echo "  Total Tests: ${total_tests}"
        echo "  Passed: ${passed_tests}"
        echo "  Failed: ${failed_tests}"
        
        if [[ "${failed_tests}" -eq 0 ]]; then
            echo "  Status: ALL TESTS PASSED"
        else
            echo "  Status: SOME TESTS FAILED"
        fi
        
    } > "${report_file}"
    
    print_success "Test report generated: ${report_file}"
}

#######################################
# Run all test suites
#######################################
run_all_tests() {
    local overall_status=0
    local test_suites=("unit" "integration" "e2e")
    
    print_info "Running all test suites..."
    
    for suite in "${test_suites[@]}"; do
        if ! run_test_suite "${suite}"; then
            overall_status=1
        fi
        echo
    done
    
    # Generate overall report
    generate_overall_report
    
    return ${overall_status}
}

#######################################
# Generate overall test report
#######################################
generate_overall_report() {
    local overall_report="${TEST_RESULTS_DIR}/overall-report.txt"
    
    print_info "Generating overall test report..."
    
    {
        echo "Overall Test Report"
        echo "Generated: $(date)"
        echo "==============================================="
        echo
        
        for suite in unit integration e2e; do
            local results_file="${TEST_RESULTS_DIR}/${suite}-results.tap"
            if [[ -f "${results_file}" ]]; then
                local total passed failed
                total=$(grep -c "^ok\|^not ok" "${results_file}" 2>/dev/null || echo "0")
                passed=$(grep -c "^ok" "${results_file}" 2>/dev/null || echo "0")
                failed=$(grep -c "^not ok" "${results_file}" 2>/dev/null || echo "0")
                
                echo "${suite^} Tests: ${passed}/${total} passed"
                [[ "${failed}" -gt 0 ]] && echo "  ${failed} FAILED"
            else
                echo "${suite^} Tests: NOT RUN"
            fi
        done
        
        echo
        echo "Test artifacts available in: ${TEST_RESULTS_DIR}"
        
    } > "${overall_report}"
    
    print_success "Overall report generated: ${overall_report}"
    
    # Display summary
    echo
    print_info "TEST SUMMARY:"
    cat "${overall_report}" | grep -E "(Tests:|FAILED|artifacts)"
}

#######################################
# Cleanup function
#######################################
cleanup() {
    if [[ "${DOCKER_MODE}" == "true" ]]; then
        stop_docker_environment
    fi
}

#######################################
# Main function
#######################################
main() {
    local test_suite="all"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--docker)
                DOCKER_MODE=true
                shift
                ;;
            -c|--no-cleanup)
                CLEANUP_ON_EXIT=false
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -p|--pattern)
                TEST_PATTERN="$2"
                shift 2
                ;;
            --unit)
                test_suite="unit"
                shift
                ;;
            --integration)
                test_suite="integration"
                shift
                ;;
            --e2e)
                test_suite="e2e"
                shift
                ;;
            --all)
                test_suite="all"
                shift
                ;;
            unit|integration|e2e|all)
                test_suite="$1"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    print_info "Starting backup system test runner"
    print_info "Test suite: ${test_suite}"
    print_info "Docker mode: ${DOCKER_MODE}"
    print_info "Verbose: ${VERBOSE}"
    
    # Setup environment
    setup_test_environment
    check_dependencies
    
    if [[ "${DOCKER_MODE}" == "true" ]]; then
        start_docker_environment
    fi
    
    # Run tests
    local exit_code=0
    case "${test_suite}" in
        all)
            run_all_tests || exit_code=$?
            ;;
        unit|integration|e2e)
            run_test_suite "${test_suite}" || exit_code=$?
            ;;
        *)
            print_error "Invalid test suite: ${test_suite}"
            exit 1
            ;;
    esac
    
    if [[ ${exit_code} -eq 0 ]]; then
        print_success "All tests completed successfully!"
    else
        print_error "Some tests failed!"
    fi
    
    exit ${exit_code}
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi