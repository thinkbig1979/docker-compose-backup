#!/bin/bash
# Setup test environment for backup system testing
# Installs dependencies and prepares test infrastructure

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTING_DIR="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT="$(dirname "${TESTING_DIR}")"

# Installation flags
INSTALL_BATS=false
INSTALL_DOCKER=false
INSTALL_RCLONE=false
INSTALL_RESTIC=false
FORCE_INSTALL=false
VERBOSE=false

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#######################################
# Display usage information
#######################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup test environment for backup system testing.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --force             Force installation even if tools exist
    --bats                  Install BATS testing framework
    --docker                Install Docker and Docker Compose
    --rclone                Install rclone
    --restic                Install restic
    --all                   Install all testing dependencies
    --check                 Check current installation status

EXAMPLES:
    $0 --check              # Check what's installed
    $0 --bats --rclone      # Install specific tools
    $0 --all                # Install everything needed for testing

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
# Check if running as root
#######################################
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Some installations may not work correctly."
        return 0
    fi
    return 1
}

#######################################
# Detect operating system
#######################################
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID}"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

#######################################
# Check installation status
#######################################
check_installation_status() {
    print_info "Checking current installation status..."
    echo
    
    # Check BATS
    if command -v bats >/dev/null 2>&1; then
        local bats_version
        bats_version=$(bats --version 2>/dev/null | head -n1 || echo "unknown")
        print_success "BATS: ${bats_version}"
    else
        print_warning "BATS: Not installed"
    fi
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            local docker_version
            docker_version=$(docker --version 2>/dev/null || echo "unknown")
            print_success "Docker: ${docker_version}"
        else
            print_warning "Docker: Installed but daemon not running"
        fi
    else
        print_warning "Docker: Not installed"
    fi
    
    # Check Docker Compose
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker-compose --version 2>/dev/null || echo "unknown")
        print_success "Docker Compose: ${compose_version}"
    else
        print_warning "Docker Compose: Not installed"
    fi
    
    # Check rclone
    if command -v rclone >/dev/null 2>&1; then
        local rclone_version
        rclone_version=$(rclone version --check=false 2>/dev/null | head -n1 || echo "unknown")
        print_success "rclone: ${rclone_version}"
    else
        print_warning "rclone: Not installed"
    fi
    
    # Check restic
    if command -v restic >/dev/null 2>&1; then
        local restic_version
        restic_version=$(restic version 2>/dev/null | head -n1 || echo "unknown")
        print_success "restic: ${restic_version}"
    else
        print_warning "restic: Not installed"
    fi
    
    # Check dialog
    if command -v dialog >/dev/null 2>&1; then
        print_success "dialog: Available"
    else
        print_warning "dialog: Not installed (needed for TUI testing)"
    fi
    
    # Check other utilities
    local utils=("jq" "curl" "wget" "git")
    for util in "${utils[@]}"; do
        if command -v "${util}" >/dev/null 2>&1; then
            print_success "${util}: Available"
        else
            print_warning "${util}: Not installed"
        fi
    done
}

#######################################
# Install BATS testing framework
#######################################
install_bats() {
    print_info "Installing BATS testing framework..."
    
    if command -v bats >/dev/null 2>&1 && [[ "${FORCE_INSTALL}" == "false" ]]; then
        print_success "BATS already installed"
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Install BATS core
    print_info "Downloading BATS core..."
    if command -v git >/dev/null 2>&1; then
        git clone https://github.com/bats-core/bats-core.git "${temp_dir}/bats-core"
        cd "${temp_dir}/bats-core"
        sudo ./install.sh /usr/local
    else
        print_error "Git is required to install BATS"
        return 1
    fi
    
    # Install BATS helper libraries
    print_info "Installing BATS helper libraries..."
    local bats_helpers_dir="/opt/bats-helpers"
    sudo mkdir -p "${bats_helpers_dir}"
    
    for repo in bats-support bats-assert bats-file; do
        print_info "Installing ${repo}..."
        sudo git clone "https://github.com/bats-core/${repo}.git" "${bats_helpers_dir}/${repo}"
    done
    
    # Set environment variable
    echo 'export BATS_LIB_PATH="/opt/bats-helpers"' | sudo tee /etc/environment.d/bats.conf >/dev/null || true
    export BATS_LIB_PATH="/opt/bats-helpers"
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    print_success "BATS installed successfully"
}

#######################################
# Install Docker and Docker Compose
#######################################
install_docker() {
    print_info "Installing Docker and Docker Compose..."
    
    if command -v docker >/dev/null 2>&1 && [[ "${FORCE_INSTALL}" == "false" ]]; then
        print_success "Docker already installed"
    else
        local os
        os=$(detect_os)
        
        case "${os}" in
            ubuntu|debian)
                install_docker_debian
                ;;
            centos|rhel|fedora)
                install_docker_redhat
                ;;
            *)
                print_error "Unsupported OS for automatic Docker installation: ${os}"
                print_info "Please install Docker manually from https://docs.docker.com/get-docker/"
                return 1
                ;;
        esac
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 || [[ "${FORCE_INSTALL}" == "true" ]]; then
        install_docker_compose
    fi
    
    # Add current user to docker group
    if ! groups | grep -q docker; then
        print_info "Adding current user to docker group..."
        sudo usermod -aG docker "${USER}"
        print_warning "Please log out and back in for docker group changes to take effect"
    fi
}

#######################################
# Install Docker on Debian/Ubuntu
#######################################
install_docker_debian() {
    print_info "Installing Docker on Debian/Ubuntu..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    sudo apt-get update
    
    # Install Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
}

#######################################
# Install Docker on Red Hat/CentOS
#######################################
install_docker_redhat() {
    print_info "Installing Docker on Red Hat/CentOS..."
    
    # Install prerequisites
    sudo yum install -y yum-utils
    
    # Add Docker repository
    sudo yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker Engine
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
}

#######################################
# Install Docker Compose
#######################################
install_docker_compose() {
    print_info "Installing Docker Compose..."
    
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [[ -z "${compose_version}" ]]; then
        compose_version="v2.21.0"  # Fallback version
        print_warning "Could not determine latest version, using ${compose_version}"
    fi
    
    # Download and install
    sudo curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    
    sudo chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker Compose ${compose_version} installed"
}

#######################################
# Install rclone
#######################################
install_rclone() {
    print_info "Installing rclone..."
    
    if command -v rclone >/dev/null 2>&1 && [[ "${FORCE_INSTALL}" == "false" ]]; then
        print_success "rclone already installed"
        return 0
    fi
    
    # Download and install rclone
    curl -sSL https://rclone.org/install.sh | sudo bash
    
    print_success "rclone installed successfully"
}

#######################################
# Install restic
#######################################
install_restic() {
    print_info "Installing restic..."
    
    if command -v restic >/dev/null 2>&1 && [[ "${FORCE_INSTALL}" == "false" ]]; then
        print_success "restic already installed"
        return 0
    fi
    
    local os
    os=$(detect_os)
    
    case "${os}" in
        ubuntu|debian)
            # Use official repository
            sudo apt-get update
            sudo apt-get install -y restic
            ;;
        centos|rhel|fedora)
            # Install from GitHub releases
            install_restic_from_github
            ;;
        *)
            install_restic_from_github
            ;;
    esac
    
    print_success "restic installed successfully"
}

#######################################
# Install restic from GitHub releases
#######################################
install_restic_from_github() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) arch="amd64" ;;
    esac
    
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/restic/restic/releases/latest | grep -Po '"tag_name": "v\K.*?(?=")')
    
    if [[ -z "${latest_version}" ]]; then
        latest_version="0.16.0"  # Fallback version
    fi
    
    local download_url="https://github.com/restic/restic/releases/download/v${latest_version}/restic_${latest_version}_linux_${arch}.bz2"
    
    print_info "Downloading restic ${latest_version}..."
    curl -L "${download_url}" -o "${temp_dir}/restic.bz2"
    
    bunzip2 "${temp_dir}/restic.bz2"
    sudo mv "${temp_dir}/restic" /usr/local/bin/restic
    sudo chmod +x /usr/local/bin/restic
    
    rm -rf "${temp_dir}"
}

#######################################
# Install additional test dependencies
#######################################
install_additional_deps() {
    print_info "Installing additional test dependencies..."
    
    local os
    os=$(detect_os)
    
    case "${os}" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y dialog jq curl wget git netcat-openbsd
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y dialog jq curl wget git netcat
            else
                sudo yum install -y dialog jq curl wget git netcat
            fi
            ;;
        *)
            print_warning "Cannot install additional dependencies automatically on ${os}"
            ;;
    esac
}

#######################################
# Setup test directories
#######################################
setup_test_directories() {
    print_info "Setting up test directories..."
    
    # Create results and coverage directories
    mkdir -p "${TESTING_DIR}/results"
    mkdir -p "${TESTING_DIR}/coverage"
    mkdir -p "${TESTING_DIR}/tmp"
    
    # Set permissions
    chmod 755 "${TESTING_DIR}/results"
    chmod 755 "${TESTING_DIR}/coverage"
    chmod 755 "${TESTING_DIR}/tmp"
    
    print_success "Test directories created"
}

#######################################
# Validate installation
#######################################
validate_installation() {
    print_info "Validating installation..."
    
    local validation_failed=false
    
    # Test BATS
    if command -v bats >/dev/null 2>&1; then
        if bats --version >/dev/null 2>&1; then
            print_success "BATS: Working"
        else
            print_error "BATS: Installed but not working"
            validation_failed=true
        fi
    fi
    
    # Test Docker
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            print_success "Docker: Working"
        else
            print_warning "Docker: Installed but daemon not accessible (may need group membership)"
        fi
    fi
    
    # Test rclone
    if command -v rclone >/dev/null 2>&1; then
        if rclone version --check=false >/dev/null 2>&1; then
            print_success "rclone: Working"
        else
            print_error "rclone: Installed but not working"
            validation_failed=true
        fi
    fi
    
    # Test restic
    if command -v restic >/dev/null 2>&1; then
        if restic version >/dev/null 2>&1; then
            print_success "restic: Working"
        else
            print_error "restic: Installed but not working"
            validation_failed=true
        fi
    fi
    
    if [[ "${validation_failed}" == "true" ]]; then
        print_error "Some tools failed validation"
        return 1
    else
        print_success "All tools validated successfully"
        return 0
    fi
}

#######################################
# Main function
#######################################
main() {
    local check_only=false
    
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
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            --bats)
                INSTALL_BATS=true
                shift
                ;;
            --docker)
                INSTALL_DOCKER=true
                shift
                ;;
            --rclone)
                INSTALL_RCLONE=true
                shift
                ;;
            --restic)
                INSTALL_RESTIC=true
                shift
                ;;
            --all)
                INSTALL_BATS=true
                INSTALL_DOCKER=true
                INSTALL_RCLONE=true
                INSTALL_RESTIC=true
                shift
                ;;
            --check)
                check_only=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    print_info "Backup System Test Environment Setup"
    echo
    
    if [[ "${check_only}" == "true" ]]; then
        check_installation_status
        exit 0
    fi
    
    # Check if any installation was requested
    if [[ "${INSTALL_BATS}" == "false" && "${INSTALL_DOCKER}" == "false" && 
          "${INSTALL_RCLONE}" == "false" && "${INSTALL_RESTIC}" == "false" ]]; then
        print_info "No installation requested. Use --check to see current status."
        print_info "Use --all to install all dependencies, or specify individual tools."
        usage
        exit 0
    fi
    
    # Setup test directories first
    setup_test_directories
    
    # Install additional dependencies
    install_additional_deps
    
    # Install requested components
    [[ "${INSTALL_BATS}" == "true" ]] && install_bats
    [[ "${INSTALL_DOCKER}" == "true" ]] && install_docker
    [[ "${INSTALL_RCLONE}" == "true" ]] && install_rclone
    [[ "${INSTALL_RESTIC}" == "true" ]] && install_restic
    
    # Validate installation
    echo
    validate_installation
    
    echo
    print_success "Test environment setup completed!"
    print_info "Run './run-tests.sh --check' to verify everything is working"
    
    if groups | grep -q docker || check_root; then
        print_info "You can now run tests with: ./run-tests.sh"
    else
        print_warning "You may need to log out and back in for Docker group membership to take effect"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi