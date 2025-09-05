#!/bin/bash
# Performance testing script for backup system
# Measures execution time, resource usage, and throughput

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTING_DIR="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT="$(dirname "${TESTING_DIR}")"

# Performance test configuration
readonly PERF_RESULTS_DIR="${TESTING_DIR}/results/performance"
readonly PERF_TEST_DATA="${TESTING_DIR}/fixtures/performance"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test parameters
TEST_DATA_SIZE="100MB"
TEST_STACK_COUNT=3
TEST_ITERATIONS=5
MONITOR_RESOURCES=true

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
# Setup performance test environment
#######################################
setup_perf_environment() {
    print_info "Setting up performance test environment..."
    
    mkdir -p "${PERF_RESULTS_DIR}"
    mkdir -p "${PERF_TEST_DATA}"
    
    # Create test data
    create_test_data_set "${TEST_DATA_SIZE}"
    
    # Create multiple test stacks
    create_test_stacks "${TEST_STACK_COUNT}"
    
    print_success "Performance test environment ready"
}

#######################################
# Create test data set
#######################################
create_test_data_set() {
    local size="$1"
    local size_bytes
    
    case "${size}" in
        *MB) size_bytes=$((${size%MB} * 1024 * 1024)) ;;
        *GB) size_bytes=$((${size%GB} * 1024 * 1024 * 1024)) ;;
        *) size_bytes="${size}" ;;
    esac
    
    print_info "Creating ${size} test dataset..."
    
    # Create various file sizes
    local test_dir="${PERF_TEST_DATA}/dataset"
    mkdir -p "${test_dir}"
    
    # Large files
    for i in {1..5}; do
        dd if=/dev/urandom of="${test_dir}/large_file_${i}.dat" bs=1024 count=$((size_bytes/5120)) 2>/dev/null
    done
    
    # Many small files
    mkdir -p "${test_dir}/small_files"
    for i in {1..100}; do
        dd if=/dev/urandom of="${test_dir}/small_files/small_${i}.txt" bs=1024 count=10 2>/dev/null
    done
    
    # Directory structure
    for i in {1..10}; do
        mkdir -p "${test_dir}/nested/level${i}"
        echo "Content ${i}" > "${test_dir}/nested/level${i}/file${i}.txt"
    done
    
    print_success "Test dataset created"
}

#######################################
# Create test stacks
#######################################
create_test_stacks() {
    local count="$1"
    
    print_info "Creating ${count} test stacks..."
    
    for ((i=1; i<=count; i++)); do
        local stack_dir="${PERF_TEST_DATA}/stacks/perftest-stack-${i}"
        mkdir -p "${stack_dir}"
        
        cat > "${stack_dir}/docker-compose.yml" << EOF
version: '3.8'

services:
  web${i}:
    image: nginx:alpine
    container_name: perftest-web-${i}
    volumes:
      - web${i}-data:/usr/share/nginx/html
      - ${PERF_TEST_DATA}/dataset:/test-data:ro
    environment:
      - STACK_ID=${i}
    
  db${i}:
    image: postgres:15-alpine
    container_name: perftest-db-${i}
    volumes:
      - db${i}-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=testdb${i}
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD=testpass

volumes:
  web${i}-data:
  db${i}-data:
EOF
    done
    
    print_success "Test stacks created"
}

#######################################
# Monitor resource usage
#######################################
monitor_process_resources() {
    local pid="$1"
    local output_file="$2"
    local interval="${3:-1}"
    
    {
        echo "timestamp,cpu_percent,memory_rss_mb,memory_vms_mb"
        while kill -0 "${pid}" 2>/dev/null; do
            if command -v ps >/dev/null 2>&1; then
                local timestamp cpu_percent memory_rss memory_vms
                timestamp=$(date +%s.%N)
                cpu_percent=$(ps -p "${pid}" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
                memory_rss=$(ps -p "${pid}" -o rss --no-headers 2>/dev/null | awk '{print $1/1024}' || echo "0")
                memory_vms=$(ps -p "${pid}" -o vsz --no-headers 2>/dev/null | awk '{print $1/1024}' || echo "0")
                
                echo "${timestamp},${cpu_percent},${memory_rss},${memory_vms}"
            fi
            sleep "${interval}"
        done
    } > "${output_file}" &
    
    echo $!
}

#######################################
# Measure execution time
#######################################
measure_execution_time() {
    local command="$1"
    local iterations="${2:-1}"
    local result_file="$3"
    
    print_info "Measuring execution time for: ${command}"
    
    local total_time=0
    local times=()
    
    for ((i=1; i<=iterations; i++)); do
        print_info "Iteration ${i}/${iterations}"
        
        local start_time end_time duration
        start_time=$(date +%s.%N)
        
        # Execute command
        if eval "${command}"; then
            end_time=$(date +%s.%N)
            duration=$(echo "${end_time} - ${start_time}" | bc)
            times+=("${duration}")
            total_time=$(echo "${total_time} + ${duration}" | bc)
            
            print_info "Iteration ${i} completed in ${duration}s"
        else
            print_error "Iteration ${i} failed"
            times+=("FAILED")
        fi
    done
    
    # Calculate statistics
    local avg_time min_time max_time
    avg_time=$(echo "scale=3; ${total_time} / ${iterations}" | bc)
    
    # Find min and max (simple approach)
    min_time="${times[0]}"
    max_time="${times[0]}"
    
    for time in "${times[@]}"; do
        if [[ "${time}" != "FAILED" ]] && command -v bc >/dev/null 2>&1; then
            if (( $(echo "${time} < ${min_time}" | bc -l) )); then
                min_time="${time}"
            fi
            if (( $(echo "${time} > ${max_time}" | bc -l) )); then
                max_time="${time}"
            fi
        fi
    done
    
    # Write results
    {
        echo "Performance Test Results"
        echo "Command: ${command}"
        echo "Iterations: ${iterations}"
        echo "Average Time: ${avg_time}s"
        echo "Min Time: ${min_time}s"
        echo "Max Time: ${max_time}s"
        echo "Total Time: ${total_time}s"
        echo ""
        echo "Individual Times:"
        for ((i=0; i<${#times[@]}; i++)); do
            echo "  Iteration $((i+1)): ${times[i]}s"
        done
    } > "${result_file}"
    
    print_success "Performance test completed - results in ${result_file}"
}

#######################################
# Test backup performance
#######################################
test_backup_performance() {
    print_info "Testing backup performance..."
    
    local test_config="${PERF_TEST_DATA}/backup.conf"
    local test_repo="${PERF_TEST_DATA}/restic-repo"
    local results_file="${PERF_RESULTS_DIR}/backup-performance.txt"
    
    # Create test configuration
    cat > "${test_config}" << EOF
BACKUP_DIR=${PERF_TEST_DATA}/stacks
BACKUP_TIMEOUT=600
DOCKER_TIMEOUT=30
RESTIC_REPOSITORY=${test_repo}
RESTIC_PASSWORD=performance-test
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=files
EOF
    
    # Initialize repository
    export RESTIC_REPOSITORY="${test_repo}"
    export RESTIC_PASSWORD="performance-test"
    restic init --repo "${test_repo}" --password-file <(echo "performance-test") >/dev/null 2>&1 || true
    
    # Test command
    local test_command="BACKUP_CONFIG=${test_config} ${PROJECT_ROOT}/docker-backup.sh --dry-run"
    
    measure_execution_time "${test_command}" "${TEST_ITERATIONS}" "${results_file}"
}

#######################################
# Test rclone performance
#######################################
test_rclone_performance() {
    print_info "Testing rclone performance..."
    
    local source_dir="${PERF_TEST_DATA}/dataset"
    local dest_dir="${PERF_TEST_DATA}/rclone-dest"
    local results_file="${PERF_RESULTS_DIR}/rclone-performance.txt"
    
    mkdir -p "${dest_dir}"
    
    # Test rclone sync performance
    local test_command="rclone sync ${source_dir} ${dest_dir} --stats 1s --stats-one-line"
    
    measure_execution_time "${test_command}" "${TEST_ITERATIONS}" "${results_file}"
}

#######################################
# Test TUI performance
#######################################
test_tui_performance() {
    print_info "Testing TUI performance..."
    
    local results_file="${PERF_RESULTS_DIR}/tui-performance.txt"
    
    # Test TUI initialization and exit
    local test_command="timeout 5s ${PROJECT_ROOT}/backup-tui.sh --help"
    
    measure_execution_time "${test_command}" "${TEST_ITERATIONS}" "${results_file}"
}

#######################################
# Test system resources during backup
#######################################
test_resource_usage() {
    print_info "Testing resource usage during backup..."
    
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker not available, skipping resource usage test"
        return 0
    fi
    
    local test_config="${PERF_TEST_DATA}/backup.conf"
    local test_repo="${PERF_TEST_DATA}/restic-repo-resources"
    local results_file="${PERF_RESULTS_DIR}/resource-usage.csv"
    
    # Create configuration
    cat > "${test_config}" << EOF
BACKUP_DIR=${PERF_TEST_DATA}/stacks
BACKUP_TIMEOUT=300
DOCKER_TIMEOUT=30
RESTIC_REPOSITORY=${test_repo}
RESTIC_PASSWORD=resource-test
EOF
    
    # Initialize repository
    export RESTIC_REPOSITORY="${test_repo}"
    export RESTIC_PASSWORD="resource-test"
    restic init --repo "${test_repo}" --password-file <(echo "resource-test") >/dev/null 2>&1 || true
    
    # Start backup process in background
    BACKUP_CONFIG="${test_config}" "${PROJECT_ROOT}/docker-backup.sh" --dry-run &
    local backup_pid=$!
    
    # Monitor resources
    local monitor_pid
    if [[ "${MONITOR_RESOURCES}" == "true" ]]; then
        monitor_pid=$(monitor_process_resources "${backup_pid}" "${results_file}" 0.5)
    fi
    
    # Wait for backup to complete
    wait "${backup_pid}"
    
    # Stop monitoring
    if [[ -n "${monitor_pid:-}" ]]; then
        kill "${monitor_pid}" 2>/dev/null || true
    fi
    
    print_success "Resource usage test completed - results in ${results_file}"
}

#######################################
# Generate performance report
#######################################
generate_performance_report() {
    local report_file="${PERF_RESULTS_DIR}/performance-summary.txt"
    
    print_info "Generating performance report..."
    
    {
        echo "Backup System Performance Test Report"
        echo "Generated: $(date)"
        echo "======================================"
        echo
        echo "Test Configuration:"
        echo "- Test Data Size: ${TEST_DATA_SIZE}"
        echo "- Test Stacks: ${TEST_STACK_COUNT}"
        echo "- Test Iterations: ${TEST_ITERATIONS}"
        echo "- Resource Monitoring: ${MONITOR_RESOURCES}"
        echo
        
        # Include individual test results
        for result_file in "${PERF_RESULTS_DIR}"/*.txt; do
            if [[ -f "${result_file}" && "${result_file}" != "${report_file}" ]]; then
                echo "$(basename "${result_file}"):"
                echo "----------------------------------------"
                cat "${result_file}"
                echo
            fi
        done
        
        # System information
        echo "System Information:"
        echo "----------------------------------------"
        echo "OS: $(uname -a)"
        echo "CPU: $(nproc) cores"
        if command -v free >/dev/null 2>&1; then
            echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
        fi
        if command -v df >/dev/null 2>&1; then
            echo "Disk: $(df -h . | tail -1 | awk '{print $4}') available"
        fi
        
    } > "${report_file}"
    
    print_success "Performance report generated: ${report_file}"
    
    # Display summary
    echo
    print_info "PERFORMANCE SUMMARY:"
    if [[ -f "${PERF_RESULTS_DIR}/backup-performance.txt" ]]; then
        echo "Backup Performance:"
        grep "Average Time:" "${PERF_RESULTS_DIR}/backup-performance.txt" || true
    fi
    
    if [[ -f "${PERF_RESULTS_DIR}/rclone-performance.txt" ]]; then
        echo "rclone Performance:"
        grep "Average Time:" "${PERF_RESULTS_DIR}/rclone-performance.txt" || true
    fi
}

#######################################
# Cleanup performance test environment
#######################################
cleanup_perf_environment() {
    print_info "Cleaning up performance test environment..."
    
    # Stop any running test containers
    for ((i=1; i<=TEST_STACK_COUNT; i++)); do
        local stack_dir="${PERF_TEST_DATA}/stacks/perftest-stack-${i}"
        if [[ -f "${stack_dir}/docker-compose.yml" ]]; then
            docker-compose -f "${stack_dir}/docker-compose.yml" down -v 2>/dev/null || true
        fi
    done
    
    # Clean up test data (optional - keep results)
    if [[ "${CLEANUP_TEST_DATA:-false}" == "true" ]]; then
        rm -rf "${PERF_TEST_DATA}"
    fi
    
    print_success "Cleanup completed"
}

#######################################
# Main function
#######################################
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --size)
                TEST_DATA_SIZE="$2"
                shift 2
                ;;
            --stacks)
                TEST_STACK_COUNT="$2"
                shift 2
                ;;
            --iterations)
                TEST_ITERATIONS="$2"
                shift 2
                ;;
            --no-monitoring)
                MONITOR_RESOURCES=false
                shift
                ;;
            --cleanup)
                CLEANUP_TEST_DATA=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --size SIZE         Test data size (default: ${TEST_DATA_SIZE})"
                echo "  --stacks COUNT      Number of test stacks (default: ${TEST_STACK_COUNT})"
                echo "  --iterations COUNT  Test iterations (default: ${TEST_ITERATIONS})"
                echo "  --no-monitoring     Disable resource monitoring"
                echo "  --cleanup          Clean up test data after completion"
                echo "  -h, --help         Show this help"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_info "Starting backup system performance tests"
    print_info "Data size: ${TEST_DATA_SIZE}, Stacks: ${TEST_STACK_COUNT}, Iterations: ${TEST_ITERATIONS}"
    
    # Setup trap for cleanup
    trap cleanup_perf_environment EXIT
    
    # Run performance tests
    setup_perf_environment
    
    test_backup_performance
    test_rclone_performance
    test_tui_performance
    
    if [[ "${MONITOR_RESOURCES}" == "true" ]]; then
        test_resource_usage
    fi
    
    generate_performance_report
    
    print_success "Performance testing completed!"
    print_info "Results available in: ${PERF_RESULTS_DIR}/"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi