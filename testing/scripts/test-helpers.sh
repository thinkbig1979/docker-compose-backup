#!/bin/bash
# Test helper functions for backup system testing
# Provides common utilities and mock functions for tests

set -euo pipefail

# Test configuration
readonly TEST_HELPERS_VERSION="1.0"

#######################################
# Test Environment Helpers
#######################################

# Create temporary test directory with cleanup
create_test_temp_dir() {
    local temp_dir
    temp_dir="$(mktemp -d -t backup-test-XXXXXX)"
    
    # Register for cleanup
    echo "${temp_dir}" >> "${TEST_CLEANUP_LIST:-/tmp/test-cleanup-$$}"
    
    echo "${temp_dir}"
}

# Cleanup all temporary directories
cleanup_test_temp_dirs() {
    local cleanup_list="${TEST_CLEANUP_LIST:-/tmp/test-cleanup-$$}"
    
    if [[ -f "${cleanup_list}" ]]; then
        while IFS= read -r temp_dir; do
            if [[ -d "${temp_dir}" ]]; then
                rm -rf "${temp_dir}"
            fi
        done < "${cleanup_list}"
        
        rm -f "${cleanup_list}"
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local check_command="$2"
    local timeout="${3:-30}"
    local interval="${4:-2}"
    
    local elapsed=0
    
    echo "Waiting for ${service_name} to be ready..."
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if eval "${check_command}" >/dev/null 2>&1; then
            echo "${service_name} is ready"
            return 0
        fi
        
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done
    
    echo "Timeout waiting for ${service_name}"
    return 1
}

# Check if Docker is available and working
is_docker_available() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

# Check if docker-compose is available
is_docker_compose_available() {
    command -v docker-compose >/dev/null 2>&1
}

# Check if rclone is available
is_rclone_available() {
    command -v rclone >/dev/null 2>&1
}

# Check if restic is available
is_restic_available() {
    command -v restic >/dev/null 2>&1
}

#######################################
# Mock Functions
#######################################

# Create mock Docker command
create_mock_docker() {
    local mock_dir="$1"
    local behavior="${2:-success}"
    
    mkdir -p "${mock_dir}"
    
    cat > "${mock_dir}/docker" << EOF
#!/bin/bash
# Mock docker command for testing

case "\$1" in
    info)
        if [[ "${behavior}" == "success" ]]; then
            echo "Docker mock - info command"
            exit 0
        else
            echo "Docker daemon not available" >&2
            exit 1
        fi
        ;;
    version)
        echo "Docker version mock"
        exit 0
        ;;
    ps)
        echo "CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES"
        echo "abc123         nginx     \"nginx\"   1 min ago Up 1 min  80/tcp    test-web"
        ;;
    exec)
        echo "Mock docker exec: \$*"
        ;;
    *)
        echo "Mock docker command: \$*"
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
esac
EOF
    
    chmod +x "${mock_dir}/docker"
    echo "${mock_dir}/docker"
}

# Create mock docker-compose command
create_mock_docker_compose() {
    local mock_dir="$1"
    local behavior="${2:-success}"
    
    mkdir -p "${mock_dir}"
    
    cat > "${mock_dir}/docker-compose" << EOF
#!/bin/bash
# Mock docker-compose command for testing

echo "Mock docker-compose: \$*" >&2

case "\$1" in
    up)
        echo "Starting services..."
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
    down)
        echo "Stopping services..."
        exit 0
        ;;
    ps)
        echo "    Name        Command      State    Ports"
        echo "test-web      nginx        Up       80/tcp"
        ;;
    *)
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
esac
EOF
    
    chmod +x "${mock_dir}/docker-compose"
    echo "${mock_dir}/docker-compose"
}

# Create mock restic command
create_mock_restic() {
    local mock_dir="$1"
    local behavior="${2:-success}"
    
    mkdir -p "${mock_dir}"
    
    cat > "${mock_dir}/restic" << EOF
#!/bin/bash
# Mock restic command for testing

echo "Mock restic: \$*" >&2

case "\$1" in
    init)
        echo "Repository initialized successfully"
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
    backup)
        echo "Backup completed successfully"
        echo "Files: 10, Dirs: 2, Added: 1024 B"
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
    snapshots)
        cat << 'SNAPSHOTS_EOF'
ID        Time                 Host        Tags        Paths
abc123    2024-01-01 12:00:00  testhost                /test-data
SNAPSHOTS_EOF
        ;;
    check)
        echo "Repository check completed successfully"
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
    *)
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
esac
EOF
    
    chmod +x "${mock_dir}/restic"
    echo "${mock_dir}/restic"
}

# Create mock rclone command
create_mock_rclone() {
    local mock_dir="$1"
    local behavior="${2:-success}"
    
    mkdir -p "${mock_dir}"
    
    cat > "${mock_dir}/rclone" << EOF
#!/bin/bash
# Mock rclone command for testing

echo "Mock rclone: \$*" >&2

case "\$1" in
    copy|sync)
        echo "Copying files..."
        echo "Transferred: 10, Errors: 0"
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
    ls)
        echo "test-file.txt"
        echo "test-dir/"
        ;;
    config)
        echo "Mock rclone config"
        ;;
    version)
        echo "rclone v1.55.1 (mock)"
        ;;
    *)
        [[ "${behavior}" == "success" ]] && exit 0 || exit 1
        ;;
esac
EOF
    
    chmod +x "${mock_dir}/rclone"
    echo "${mock_dir}/rclone"
}

# Create mock dialog command
create_mock_dialog() {
    local mock_dir="$1"
    local responses_file="${2:-}"
    
    mkdir -p "${mock_dir}"
    
    cat > "${mock_dir}/dialog" << EOF
#!/bin/bash
# Mock dialog command for testing

echo "Mock dialog: \$*" >&2

# Read response from file if provided
if [[ -n "${responses_file}" && -f "${responses_file}" ]]; then
    read -r response < "${responses_file}"
    echo "\${response}"
    # Remove first line from responses file
    sed -i '1d' "${responses_file}"
else
    # Default responses based on dialog type
    case "\$*" in
        *--yesno*)
            exit 0  # Yes
            ;;
        *--menu*)
            echo "1"  # First option
            ;;
        *--inputbox*)
            echo "mock-input"
            ;;
        *--msgbox*)
            exit 0
            ;;
        *)
            echo "mock-output"
            ;;
    esac
fi
EOF
    
    chmod +x "${mock_dir}/dialog"
    echo "${mock_dir}/dialog"
}

#######################################
# Test Data Generators
#######################################

# Create test Docker compose file
create_test_docker_compose() {
    local compose_file="$1"
    local service_name="${2:-test-service}"
    local image="${3:-nginx:alpine}"
    
    mkdir -p "$(dirname "${compose_file}")"
    
    cat > "${compose_file}" << EOF
version: '3.8'

services:
  ${service_name}:
    image: ${image}
    container_name: ${service_name}-container
    volumes:
      - ${service_name}-data:/data
    environment:
      - TEST_ENV=true
    restart: unless-stopped

volumes:
  ${service_name}-data:
EOF
    
    echo "${compose_file}"
}

# Create test backup configuration
create_test_backup_config() {
    local config_file="$1"
    local backup_dir="$2"
    local restic_repo="$3"
    local restic_password="${4:-test-password}"
    
    mkdir -p "$(dirname "${config_file}")"
    
    cat > "${config_file}" << EOF
# Test backup configuration
BACKUP_DIR=${backup_dir}
BACKUP_TIMEOUT=60
DOCKER_TIMEOUT=10
RESTIC_REPOSITORY=${restic_repo}
RESTIC_PASSWORD=${restic_password}

# Test-specific settings
ENABLE_BACKUP_VERIFICATION=true
VERIFICATION_DEPTH=files
MIN_DISK_SPACE_MB=50
ENABLE_JSON_LOGGING=true
EOF
    
    echo "${config_file}"
}

# Create test rclone configuration
create_test_rclone_config() {
    local config_file="$1"
    local remote_name="${2:-test-remote}"
    local remote_type="${3:-local}"
    
    mkdir -p "$(dirname "${config_file}")"
    
    cat > "${config_file}" << EOF
# Test rclone configuration
[${remote_name}]
type = ${remote_type}
EOF
    
    if [[ "${remote_type}" == "s3" ]]; then
        cat >> "${config_file}" << EOF
provider = Minio
access_key_id = testuser
secret_access_key = testpass123
endpoint = http://localhost:9000
EOF
    fi
    
    echo "${config_file}"
}

# Create test data files
create_test_data() {
    local data_dir="$1"
    local file_count="${2:-5}"
    local file_size="${3:-1024}"
    
    mkdir -p "${data_dir}"
    
    for ((i=1; i<=file_count; i++)); do
        local file_path="${data_dir}/test-file-${i}.txt"
        dd if=/dev/urandom of="${file_path}" bs="${file_size}" count=1 2>/dev/null
        echo "Test content ${i}" >> "${file_path}"
    done
    
    # Create subdirectory with files
    mkdir -p "${data_dir}/subdir"
    echo "Subdirectory test content" > "${data_dir}/subdir/nested-file.txt"
    
    echo "${data_dir}"
}

#######################################
# Assertion Helpers
#######################################

# Assert that a service is running
assert_service_running() {
    local service_name="$1"
    local container_name="${2:-${service_name}}"
    
    if is_docker_available; then
        if docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            return 0
        else
            echo "Service ${service_name} (${container_name}) is not running" >&2
            return 1
        fi
    else
        echo "Docker not available, cannot check service" >&2
        return 1
    fi
}

# Assert that a backup repository exists
assert_restic_repo_exists() {
    local repo_path="$1"
    local password="$2"
    
    if is_restic_available; then
        if restic snapshots --repo "${repo_path}" --password-file <(echo "${password}") >/dev/null 2>&1; then
            return 0
        else
            echo "Restic repository not found or inaccessible: ${repo_path}" >&2
            return 1
        fi
    else
        echo "Restic not available, cannot check repository" >&2
        return 1
    fi
}

# Assert that files have been synced
assert_files_synced() {
    local source_dir="$1"
    local dest_dir="$2"
    
    local source_count dest_count
    source_count=$(find "${source_dir}" -type f | wc -l)
    dest_count=$(find "${dest_dir}" -type f | wc -l)
    
    if [[ "${source_count}" -eq "${dest_count}" ]]; then
        return 0
    else
        echo "File sync mismatch: source ${source_count}, dest ${dest_count}" >&2
        return 1
    fi
}

#######################################
# Performance Testing Helpers
#######################################

# Measure execution time
measure_execution_time() {
    local command="$1"
    local start_time end_time duration
    
    start_time=$(date +%s.%N)
    eval "${command}"
    local exit_code=$?
    end_time=$(date +%s.%N)
    
    duration=$(echo "${end_time} - ${start_time}" | bc)
    echo "Execution time: ${duration}s" >&2
    
    return ${exit_code}
}

# Monitor resource usage during test
monitor_resources() {
    local pid="$1"
    local output_file="$2"
    local interval="${3:-1}"
    
    {
        echo "timestamp,cpu_percent,memory_mb"
        while kill -0 "${pid}" 2>/dev/null; do
            local timestamp cpu_percent memory_mb
            timestamp=$(date +%s)
            
            if command -v ps >/dev/null 2>&1; then
                cpu_percent=$(ps -p "${pid}" -o %cpu --no-headers 2>/dev/null || echo "0")
                memory_mb=$(ps -p "${pid}" -o rss --no-headers 2>/dev/null | awk '{print $1/1024}')
            else
                cpu_percent="0"
                memory_mb="0"
            fi
            
            echo "${timestamp},${cpu_percent},${memory_mb}"
            sleep "${interval}"
        done
    } > "${output_file}" &
    
    echo $!
}

#######################################
# Initialization
#######################################

# Setup test helpers environment
setup_test_helpers() {
    # Set cleanup list file
    export TEST_CLEANUP_LIST="/tmp/test-cleanup-$$"
    
    # Register cleanup function
    trap cleanup_test_temp_dirs EXIT
    
    echo "Test helpers ${TEST_HELPERS_VERSION} initialized"
}

# Initialize if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    setup_test_helpers
fi