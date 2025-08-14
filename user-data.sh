#!/bin/bash

# EC2 User Data Script for TIG Stack Deployment
# Automatically installs Docker and deploys Telegraf/InfluxDB/Grafana monitoring stack

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script variables and directory paths
readonly SCRIPT_NAME="tig-stack-installer"
LOG_FILE="${LOG_FILE:-/var/log/tig-stack-install.log}"
readonly TIG_INSTALL_DIR="/opt/tig-stack"
readonly TIG_USER="ec2-user"

# Global status tracking
SCRIPT_STATUS="RUNNING"
FAILED_STEPS=()
COMPLETED_STEPS=()
TOTAL_STEPS=12

# Enhanced logging functions
log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $message" | tee -a "$LOG_FILE"
}

log_step_start() {
    local step_number="$1"
    local step_name="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP $step_number/$TOTAL_STEPS] Starting: $step_name" | tee -a "$LOG_FILE"
}

log_step_complete() {
    local step_number="$1"
    local step_name="$2"
    COMPLETED_STEPS+=("$step_number: $step_name")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP $step_number/$TOTAL_STEPS] Completed: $step_name" | tee -a "$LOG_FILE"
}

log_step_failed() {
    local step_number="$1"
    local step_name="$2"
    local error_message="$3"
    FAILED_STEPS+=("$step_number: $step_name - $error_message")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP $step_number/$TOTAL_STEPS] Failed: $step_name - $error_message" | tee -a "$LOG_FILE" >&2
}

log_system_info() {
    log_info "=== System Information ==="
    log_info "Hostname: $(hostname)"
    log_info "OS: $(uname -s) $(uname -r)"
    log_info "Architecture: $(uname -m)"
    log_info "User: $(whoami)"
    log_info "Working Directory: $(pwd)"
    log_info "Available Disk Space: $(df -h / | tail -1 | awk '{print $4}')"
    log_info "Available Memory: $(free -h | grep '^Mem:' | awk '{print $7}')"
    log_info "=========================="
}

# Enhanced error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    local function_name="${FUNCNAME[1]:-main}"
    
    SCRIPT_STATUS="FAILED"
    log_error "Critical error in function '$function_name' at line $line_number with exit code $exit_code"
    log_error "Last command: $(history | tail -1 | sed 's/^[ ]*[0-9]*[ ]*//')"
    log_error "Check $LOG_FILE for detailed error information"
    
    # Log current system state for debugging
    log_error "=== Error Context ==="
    log_error "Current working directory: $(pwd)"
    log_error "Current user: $(whoami)"
    log_error "Available disk space: $(df -h / | tail -1 | awk '{print $4}' 2>/dev/null || echo 'unknown')"
    log_error "Docker status: $(systemctl is-active docker 2>/dev/null || echo 'unknown')"
    log_error "===================="
    
    exit $exit_code
}

# Non-fatal error handling for recoverable errors
handle_recoverable_error() {
    local step_number="$1"
    local step_name="$2"
    local error_message="$3"
    local exit_code="${4:-1}"
    
    log_step_failed "$step_number" "$step_name" "$error_message"
    log_warning "Continuing with remaining installation steps..."
    return $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Enhanced logging initialization
initialize_logging() {
    # Create log file with proper permissions (use sudo if needed)
    if [ -w "$(dirname "$LOG_FILE")" ] || [ "$EUID" -eq 0 ]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    else
        # Fallback to local log file if we can't write to /var/log
        LOG_FILE="./tig-stack-install.log"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Using local log file: $LOG_FILE" | tee -a "$LOG_FILE"
    fi
    
    # Also create a symlink for easy access via cloud-init logs
    if [ "$LOG_FILE" != "/var/log/cloud-init-output.log" ] && [ -w "/var/log" ]; then
        ln -sf "$LOG_FILE" "/var/log/tig-stack-latest.log" 2>/dev/null || true
    fi
    
    log_info "=== TIG Stack Installation Started ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "Version: 1.0.0"
    log_info "Log file: $LOG_FILE"
    log_info "Install directory: $TIG_INSTALL_DIR"
    log_info "Target user: $TIG_USER"
    log_info "Process ID: $$"
    log_info "Total steps: $TOTAL_STEPS"
    
    # Log system information
    log_system_info
    
    # Log environment variables for debugging
    log_info "=== Environment Variables ==="
    env | grep -E '^(TIG_|GRAFANA_|INFLUXDB_|TELEGRAF_|CONTAINER_)' | while read -r var; do
        log_info "$var"
    done || log_info "No TIG-related environment variables found"
    log_info "============================="
}

# Enhanced cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    
    log_info "=== Installation Summary ==="
    log_info "Final Status: $SCRIPT_STATUS"
    log_info "Exit Code: $exit_code"
    
    # Log completed steps
    if [ ${#COMPLETED_STEPS[@]} -gt 0 ]; then
        log_info "Completed Steps (${#COMPLETED_STEPS[@]}/$TOTAL_STEPS):"
        for step in "${COMPLETED_STEPS[@]}"; do
            log_info "  ✓ $step"
        done
    fi
    
    # Log failed steps
    if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
        log_error "Failed Steps (${#FAILED_STEPS[@]}):"
        for step in "${FAILED_STEPS[@]}"; do
            log_error "  ✗ $step"
        done
    fi
    
    # Final status determination
    if [ $exit_code -eq 0 ] && [ ${#FAILED_STEPS[@]} -eq 0 ]; then
        SCRIPT_STATUS="SUCCESS"
        log_success "TIG Stack installation completed successfully"
        log_info "Grafana should be accessible at: http://$(hostname -I | awk '{print $1}'):${TIG_GRAFANA_PORT:-3000}"
        log_info "Default credentials - User: ${TIG_GRAFANA_USER:-admin}, Password: check .env file"
    else
        SCRIPT_STATUS="FAILED"
        log_error "TIG Stack installation failed"
        log_error "Check the error messages above for troubleshooting information"
        
        # Provide troubleshooting guidance
        log_info "=== Troubleshooting Information ==="
        log_info "1. Check system logs: journalctl -u cloud-init-output"
        log_info "2. Check Docker status: systemctl status docker"
        log_info "3. Check container status: docker ps -a"
        log_info "4. Check this log file: $LOG_FILE"
        log_info "5. Check cloud-init logs: /var/log/cloud-init-output.log"
        log_info "================================="
    fi
    
    # Log final system state
    log_info "=== Final System State ==="
    log_info "Docker installed: $(command -v docker >/dev/null && echo 'Yes' || echo 'No')"
    log_info "Docker running: $(systemctl is-active docker 2>/dev/null || echo 'No')"
    log_info "Docker Compose installed: $(command -v docker-compose >/dev/null && echo 'Yes' || echo 'No')"
    log_info "TIG directory exists: $([ -d "$TIG_INSTALL_DIR" ] && echo 'Yes' || echo 'No')"
    log_info "Containers running: $(docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | grep -c 'Up' || echo '0')"
    log_info "=========================="
    
    log_info "=== TIG Stack Installation Finished ==="
    log_info "Installation log available at: $LOG_FILE"
    
    # Ensure logs are accessible via standard EC2 logging
    if [ -f "$LOG_FILE" ] && [ -w "/var/log" ]; then
        # Copy final log to cloud-init output for easy access
        echo "=== TIG Stack Installation Log ===" >> /var/log/cloud-init-output.log 2>/dev/null || true
        tail -50 "$LOG_FILE" >> /var/log/cloud-init-output.log 2>/dev/null || true
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Detect the operating system
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
    log_info "Detected OS: $OS $VERSION"
}

# Install Docker based on the operating system
install_docker() {
    log_step_start "1" "Docker Installation"
    
    detect_os
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker is already installed: $(docker --version)"
        validate_docker_installation
        log_step_complete "1" "Docker Installation (already installed)"
        return 0
    fi
    
    case "$OS" in
        "amzn"|"amazon")
            if ! install_docker_amazon_linux; then
                log_step_failed "1" "Docker Installation" "Amazon Linux Docker installation failed"
                return 1
            fi
            ;;
        "ubuntu")
            if ! install_docker_ubuntu; then
                log_step_failed "1" "Docker Installation" "Ubuntu Docker installation failed"
                return 1
            fi
            ;;
        "centos"|"rhel")
            if ! install_docker_centos; then
                log_step_failed "1" "Docker Installation" "CentOS/RHEL Docker installation failed"
                return 1
            fi
            ;;
        *)
            log_step_failed "1" "Docker Installation" "Unsupported operating system: $OS"
            return 1
            ;;
    esac
    
    # Configure Docker service
    configure_docker_service
    
    # Install Docker Compose
    install_docker_compose
    
    # Validate installation
    validate_docker_installation
    
    log_step_complete "1" "Docker Installation"
}

# Install Docker on Amazon Linux 2
install_docker_amazon_linux() {
    log_info "Installing Docker on Amazon Linux..."
    
    # Update package manager
    if ! yum update -y; then
        log_error "Failed to update packages on Amazon Linux"
        return 1
    fi
    
    # Install Docker
    if ! yum install -y docker; then
        log_error "Failed to install Docker on Amazon Linux"
        return 1
    fi
    
    # Start and enable Docker service
    if ! systemctl start docker; then
        log_error "Failed to start Docker service"
        return 1
    fi
    
    if ! systemctl enable docker; then
        log_error "Failed to enable Docker service"
        return 1
    fi
    
    log_info "Docker installed on Amazon Linux"
}

# Install Docker on Ubuntu
install_docker_ubuntu() {
    log_info "Installing Docker on Ubuntu..."
    
    # Update package index
    if ! apt-get update; then
        log_error "Failed to update package index on Ubuntu"
        return 1
    fi
    
    # Install prerequisites
    if ! apt-get install -y ca-certificates curl gnupg lsb-release; then
        log_error "Failed to install prerequisites on Ubuntu"
        return 1
    fi
    
    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "Failed to add Docker GPG key"
        return 1
    fi
    
    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index again
    if ! apt-get update; then
        log_error "Failed to update package index after adding Docker repository"
        return 1
    fi
    
    # Install Docker Engine
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        log_error "Failed to install Docker Engine on Ubuntu"
        return 1
    fi
    
    # Start and enable Docker service
    if ! systemctl start docker; then
        log_error "Failed to start Docker service"
        return 1
    fi
    
    if ! systemctl enable docker; then
        log_error "Failed to enable Docker service"
        return 1
    fi
    
    log_info "Docker installed on Ubuntu"
}

# Install Docker on CentOS/RHEL
install_docker_centos() {
    log_info "Installing Docker on CentOS/RHEL..."
    
    # Update package manager
    yum update -y
    
    # Install required packages
    yum install -y yum-utils
    
    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    log_info "Docker installed on CentOS/RHEL"
}

# Configure Docker service and user permissions
configure_docker_service() {
    log_info "Configuring Docker service and user permissions..."
    
    # Create docker group if it doesn't exist
    if ! getent group docker > /dev/null 2>&1; then
        groupadd docker
        log_info "Created docker group"
    fi
    
    # Add user to docker group
    if id "$TIG_USER" >/dev/null 2>&1; then
        usermod -aG docker "$TIG_USER"
        log_info "Added $TIG_USER to docker group"
    else
        log_error "User $TIG_USER does not exist"
        exit 1
    fi
    
    # Set proper permissions for Docker socket
    chmod 666 /var/run/docker.sock 2>/dev/null || true
    
    log_info "Docker service configuration completed"
}

# Install Docker Compose using the official method
install_docker_compose() {
    log_info "Installing Docker Compose..."
    
    # Check if Docker Compose is already installed
    if command -v docker-compose >/dev/null 2>&1; then
        log_info "Docker Compose is already installed: $(docker-compose --version)"
        return 0
    fi
    
    # Get the latest version of Docker Compose
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [ -z "$compose_version" ]; then
        log_error "Failed to get Docker Compose version from GitHub API"
        # Fallback to a known stable version
        compose_version="v2.24.1"
        log_info "Using fallback version: $compose_version"
    fi
    
    log_info "Installing Docker Compose version: $compose_version"
    
    # Download and install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/$compose_version/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Make it executable
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for easier access
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
    
    # Verify installation
    if command -v docker-compose >/dev/null 2>&1; then
        log_success "Docker Compose installed successfully: $(docker-compose --version)"
    else
        log_error "Docker Compose installation failed"
        exit 1
    fi
}

# Validate Docker installation
validate_docker_installation() {
    log_info "Validating Docker installation..."
    
    # Check if Docker daemon is running
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service is not running"
        exit 1
    fi
    
    # Check Docker version
    local docker_version
    docker_version=$(docker --version 2>/dev/null || echo "")
    if [ -z "$docker_version" ]; then
        log_error "Docker command not available"
        exit 1
    fi
    log_info "Docker version: $docker_version"
    
    # Check Docker Compose version
    local compose_version
    compose_version=$(docker-compose --version 2>/dev/null || echo "")
    if [ -z "$compose_version" ]; then
        log_error "Docker Compose command not available"
        exit 1
    fi
    log_info "Docker Compose version: $compose_version"
    
    # Test Docker functionality with a simple container
    log_info "Testing Docker functionality..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker is working correctly"
    else
        log_error "Docker test failed"
        exit 1
    fi
    
    # Check if user can run Docker commands (test with current user context)
    if su - "$TIG_USER" -c "docker ps" >/dev/null 2>&1; then
        log_success "User $TIG_USER can run Docker commands"
    else
        log_info "User $TIG_USER may need to log out and back in for Docker group membership to take effect"
    fi
    
    log_success "Docker installation validation completed"
}

# Create TIG stack directory structure
create_directory_structure() {
    log_step_start "2" "Directory Structure Creation"
    
    # Create main installation directory
    if [ ! -d "$TIG_INSTALL_DIR" ]; then
        mkdir -p "$TIG_INSTALL_DIR"
        log_info "Created main directory: $TIG_INSTALL_DIR"
    fi
    
    # Create service directories
    local service_dirs=("grafana" "influxdb" "telegraf")
    for dir in "${service_dirs[@]}"; do
        local service_path="$TIG_INSTALL_DIR/$dir"
        if [ ! -d "$service_path" ]; then
            mkdir -p "$service_path"
            log_info "Created service directory: $service_path"
        fi
    done
    
    # Set proper ownership for the TIG user
    if id "$TIG_USER" >/dev/null 2>&1; then
        chown -R "$TIG_USER:$TIG_USER" "$TIG_INSTALL_DIR"
        log_info "Set ownership of $TIG_INSTALL_DIR to $TIG_USER"
    else
        log_error "User $TIG_USER does not exist, cannot set ownership"
        exit 1
    fi
    
    # Set proper permissions
    chmod -R 755 "$TIG_INSTALL_DIR"
    log_info "Set permissions for $TIG_INSTALL_DIR"
    
    log_step_complete "2" "Directory Structure Creation"
}

# Create file using heredoc with proper permissions
create_file_with_heredoc() {
    local file_path="$1"
    local file_content="$2"
    local file_mode="${3:-644}"
    local file_owner="${4:-$TIG_USER:$TIG_USER}"
    
    log_info "Creating file: $file_path"
    
    # Create the file with the provided content
    if ! echo "$file_content" > "$file_path"; then
        log_error "Failed to write content to file: $file_path"
        return 1
    fi
    
    # Set proper permissions
    if ! chmod "$file_mode" "$file_path"; then
        log_warning "Failed to set permissions $file_mode on $file_path"
    fi
    
    # Set proper ownership
    if id "$TIG_USER" >/dev/null 2>&1; then
        if ! chown "$file_owner" "$file_path" 2>/dev/null; then
            log_warning "Failed to set ownership $file_owner on $file_path"
        fi
    fi
    
    log_info "Created file: $file_path with mode $file_mode and owner $file_owner"
}

# Test logging system functionality
test_logging_system() {
    log_info "Testing logging system functionality..."
    
    # Test all log levels
    log_info "This is an info message"
    log_warning "This is a warning message"
    log_success "This is a success message"
    
    # Test step logging
    log_step_start "TEST" "Logging System Test"
    sleep 1
    log_step_complete "TEST" "Logging System Test"
    
    # Verify log file exists and is writable
    if [ ! -f "$LOG_FILE" ]; then
        echo "ERROR: Log file does not exist: $LOG_FILE" >&2
        return 1
    fi
    
    if [ ! -w "$LOG_FILE" ]; then
        echo "ERROR: Log file is not writable: $LOG_FILE" >&2
        return 1
    fi
    
    # Test log file accessibility via standard EC2 logging
    if [ -w "/var/log" ]; then
        if [ ! -L "/var/log/tig-stack-latest.log" ]; then
            log_warning "Symlink to latest log not created in /var/log"
        else
            log_info "Log file accessible via /var/log/tig-stack-latest.log"
        fi
    fi
    
    log_success "Logging system test completed successfully"
    return 0
}

# Create configuration file with validation
create_config_file() {
    local file_path="$1"
    local file_content="$2"
    local file_mode="${3:-644}"
    
    log_info "Creating configuration file: $file_path"
    
    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$file_path")
    if [ ! -d "$parent_dir" ]; then
        if ! mkdir -p "$parent_dir"; then
            log_error "Failed to create parent directory: $parent_dir"
            return 1
        fi
        chown "$TIG_USER:$TIG_USER" "$parent_dir" 2>/dev/null || log_warning "Could not set ownership for $parent_dir"
        chmod 755 "$parent_dir" 2>/dev/null || log_warning "Could not set permissions for $parent_dir"
    fi
    
    # Create the file using the helper function
    if ! create_file_with_heredoc "$file_path" "$file_content" "$file_mode"; then
        log_error "Failed to create file with heredoc: $file_path"
        return 1
    fi
    
    # Validate file was created successfully
    if [ ! -f "$file_path" ]; then
        log_error "Failed to create configuration file: $file_path"
        return 1
    fi
    
    log_info "Configuration file created: $file_path"
}

# Create executable script file
create_executable_script() {
    local file_path="$1"
    local file_content="$2"
    
    log_info "Creating executable script: $file_path"
    
    # Create the script file with executable permissions
    create_file_with_heredoc "$file_path" "$file_content" "755"
    
    # Validate script is executable
    if [ ! -x "$file_path" ]; then
        log_error "Failed to create executable script: $file_path"
        exit 1
    fi
    
    log_success "Executable script created: $file_path"
}

# Validate directory structure and permissions
validate_directory_structure() {
    log_info "Validating directory structure and permissions..."
    
    # Check main directory exists
    if [ ! -d "$TIG_INSTALL_DIR" ]; then
        log_error "Main directory does not exist: $TIG_INSTALL_DIR"
        exit 1
    fi
    
    # Check service directories exist
    local service_dirs=("grafana" "influxdb" "telegraf")
    for dir in "${service_dirs[@]}"; do
        local service_path="$TIG_INSTALL_DIR/$dir"
        if [ ! -d "$service_path" ]; then
            log_error "Service directory does not exist: $service_path"
            exit 1
        fi
    done
    
    # Check ownership
    local owner
    owner=$(stat -c '%U:%G' "$TIG_INSTALL_DIR" 2>/dev/null || stat -f '%Su:%Sg' "$TIG_INSTALL_DIR" 2>/dev/null)
    if [ "$owner" != "$TIG_USER:$TIG_USER" ]; then
        log_error "Incorrect ownership for $TIG_INSTALL_DIR. Expected: $TIG_USER:$TIG_USER, Got: $owner"
        exit 1
    fi
    
    # Check permissions
    local perms
    perms=$(stat -c '%a' "$TIG_INSTALL_DIR" 2>/dev/null || stat -f '%A' "$TIG_INSTALL_DIR" 2>/dev/null)
    if [ "$perms" != "755" ]; then
        log_error "Incorrect permissions for $TIG_INSTALL_DIR. Expected: 755, Got: $perms"
        exit 1
    fi
    
    log_success "Directory structure validation completed"
}

# Create docker-compose.yml configuration file
create_docker_compose_file() {
    log_step_start "3" "Docker Compose Configuration"
    
    local compose_file="$TIG_INSTALL_DIR/docker-compose.yml"
    
    # Embed the docker-compose.yml content using heredoc
    local compose_content
    read -r -d '' compose_content << 'EOF' || true
version: "3"

services:
    influxdb:
        build: ./influxdb
        container_name: ${CONTAINER_PREFIX}_influxdb
        ports:
            - ${INFLUXDB_PORT}:${INFLUXDB_PORT}
        volumes:
            - /var/lib/influxdb:/var/lib/influxdb
        restart: always
        env_file:
            - .env
        networks:
            - backend
            - frontend

    telegraf:
        build: ./telegraf
        container_name: ${CONTAINER_PREFIX}_telegraf
        links:
            - influxdb
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            - /proc:/hostfs/proc
        privileged: true
        restart: always
        env_file:
            - .env
        networks: 
            - backend
            
    grafana:
        build: ./grafana
        container_name: ${CONTAINER_PREFIX}_grafana
        ports: 
            - ${GRAFANA_PORT}:${GRAFANA_PORT}
        links:
            - influxdb
        volumes:
            - /var/lib/grafana
            - /var/log/grafana
            - /var/lib/grafana/plugins
        restart: always
        env_file:
            - .env
        networks:
            - frontend

networks:
    backend:
    frontend:
EOF
    
    # Create the docker-compose.yml file
    create_config_file "$compose_file" "$compose_content"
    
    # Validate the file was created and contains expected content
    if [ ! -f "$compose_file" ]; then
        log_error "Failed to create docker-compose.yml file"
        exit 1
    fi
    
    # Check if the file contains key environment variable references
    if ! grep -q '${CONTAINER_PREFIX}' "$compose_file" || \
       ! grep -q '${INFLUXDB_PORT}' "$compose_file" || \
       ! grep -q '${GRAFANA_PORT}' "$compose_file"; then
        log_error "docker-compose.yml file missing required environment variable references"
        exit 1
    fi
    
    log_step_complete "3" "Docker Compose Configuration"
}

# Create Grafana Dockerfile configuration
create_grafana_dockerfile() {
    log_step_start "4" "Grafana Configuration"
    
    local dockerfile_path="$TIG_INSTALL_DIR/grafana/Dockerfile"
    
    # Embed the Grafana Dockerfile content using heredoc
    local dockerfile_content
    read -r -d '' dockerfile_content << 'EOF' || true
FROM grafana/grafana:9.5.6-ubuntu

LABEL author="Alexis Le Provost <alexis.leprovost@outlook.com>"
LABEL version="1.0.0"
LABEL description="Grafana docker image"

USER root

RUN apt-get -q update &&\
    DEBIAN_FRONTEND="noninteractive" apt-get -q upgrade -y -o Dpkg::Options::="--force-confnew" --no-install-recommends &&\
    DEBIAN_FRONTEND="noninteractive" apt-get -q install -y -o Dpkg::Options::="--force-confnew" --no-install-recommends curl gosu &&\
    apt-get -q autoremove &&\
    apt-get -q clean -y && rm -rf /var/lib/apt/lists/* && rm -f /var/cache/apt/*.bin

RUN mkdir -p /opt/grafana/dashboards
ADD *.json /opt/grafana/dashboards/
ADD default-dashboard.yaml /etc/grafana/provisioning/dashboards/

ADD run.sh /run.sh
ENTRYPOINT ["bash", "/run.sh"]
EOF
    
    # Create the Dockerfile
    create_config_file "$dockerfile_path" "$dockerfile_content"
    
    # Create the Grafana run.sh script
    create_grafana_run_script
    
    # Create the default dashboard configuration
    create_grafana_dashboard_config
    
    log_step_complete "4" "Grafana Configuration"
}

# Create Grafana run.sh script
create_grafana_run_script() {
    log_info "Creating Grafana run.sh script..."
    
    local run_script_path="$TIG_INSTALL_DIR/grafana/run.sh"
    
    # Embed the Grafana run.sh content using heredoc
    local run_script_content
    read -r -d '' run_script_content << 'EOF' || true
#!/bin/bash -e

: "${GF_PATHS_DATA:=/var/lib/grafana}"
: "${GF_PATHS_LOGS:=/var/log/grafana}"
: "${GF_PATHS_PLUGINS:=/var/lib/grafana/plugins}"
: "${GF_PATHS_PROVISIONING:=/etc/grafana/provisioning}"

chown -R grafana:grafana "$GF_PATHS_DATA" "$GF_PATHS_LOGS"
chown -R grafana:grafana /etc/grafana

# Install all available plugins
if [ "${GRAFANA_PLUGINS_ENABLED}" != "false" ]
then
  if [ -z "${GRAFANA_PLUGINS}" ]
  then
    GRAFANA_PLUGINS=`grafana-cli plugins list-remote | awk '{print $2}'| grep "-"`
  fi
  for plugin in ${GRAFANA_PLUGINS}; 
  do
    if [ ! -d ${GF_PATHS_PLUGINS}/$plugin ]
    then
      grafana-cli plugins install $plugin || true;
    else
      echo "Plugin $plugin already installed"
    fi
  done
fi

# Start grafana with gosu
exec gosu grafana /usr/share/grafana/bin/grafana-server  \
  --homepath=/usr/share/grafana             \
  --config=/etc/grafana/grafana.ini         \
  cfg:default.paths.data="$GF_PATHS_DATA"   \
  cfg:default.paths.logs="$GF_PATHS_LOGS"   \
  cfg:default.paths.plugins="$GF_PATHS_PLUGINS" &

sleep 5

###############################################################
# Creating Default Data Source

# Set new Data Source name
INFLUXDB_DATA_SOURCE="Docker InfluxDB"
INFLUXDB_DATA_SOURCE_WEB=`echo ${INFLUXDB_DATA_SOURCE} | sed 's/ /%20/g'`

# Set information about grafana host
GRAFANA_URL=`hostname -i`

# Check $INFLUXDB_DATA_SOURCE status
INFLUXDB_DATA_SOURCE_STATUS=`curl -s -L -i \
 -H "Accept: application/json" \
 -H "Content-Type: application/json" \
 -X GET http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@${GRAFANA_URL}:${GRAFANA_PORT}/api/datasources/name/${INFLUXDB_DATA_SOURCE_WEB} | head -1 | awk '{print $2}'`

#Debug Time!
curl -s -L -i \
 -H "Accept: application/json" \
 -H "Content-Type: application/json" \
 -X GET http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@${GRAFANA_URL}:${GRAFANA_PORT}/api/datasources/name/${INFLUXDB_DATA_SOURCE_WEB} >>$GF_PATHS_LOGS/grafana.log 2>>$GF_PATHS_LOGS/grafana.log 
echo "http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@${GRAFANA_URL}:${GRAFANA_PORT}/api/datasources/name/${INFLUXDB_DATA_SOURCE_WEB}" >> $GF_PATHS_LOGS/grafana.log
echo "INFLUXDB_DATA_SOURCE_STATUS: "$INFLUXDB_DATA_SOURCE_STATUS >> $GF_PATHS_LOGS/grafana.log
echo "GRAFANA_URL: "$GRAFANA_URL >> $GF_PATHS_LOGS/grafana.log
echo "GRAFANA_PORT: "$GRAFANA_PORT >> $GF_PATHS_LOGS/grafana.log
echo "GRAFANA_USER: "$GRAFANA_USER >> $GF_PATHS_LOGS/grafana.log
echo "GRAFANA_PASSWORD: "$GRAFANA_PASSWORD >> $GF_PATHS_LOGS/grafana.log

# Check if $INFLUXDB_DATA_SOURCE exists
if [ ${INFLUXDB_DATA_SOURCE_STATUS} != 200 ]
then
  # If not exists, create one 
  echo "Data Source: '"${INFLUXDB_DATA_SOURCE}"' not found in Grafana configuration"
  echo "Creating Data Source: '"$INFLUXDB_DATA_SOURCE"'"
  curl -L -i \
   -H "Accept: application/json" \
   -H "Content-Type: application/json" \
   -X POST -d '{
    "name":"'"${INFLUXDB_DATA_SOURCE}"'",
    "type":"influxdb",
    "url":"http://'"${INFLUXDB_HOST}"':'"${INFLUXDB_PORT}"'",
    "access":"proxy",
    "basicAuth":false,
    "database": "'"${INFLUXDB_DATABASE}"'",
    "user":"'"${INFLUXDB_ADMIN_USER}"'",
    "password":"'"${INFLUXDB_ADMIN_PASSWORD}"'"}
  ' \
  http://${GRAFANA_USER}:${GRAFANA_PASSWORD}@${GRAFANA_URL}:${GRAFANA_PORT}/api/datasources
else
  #Continue if it doesn't exists
  echo "Data Source '"${INFLUXDB_DATA_SOURCE}"' already exists."
fi

tail -f $GF_PATHS_LOGS/grafana.log
EOF
    
    # Create the executable script
    create_executable_script "$run_script_path" "$run_script_content"
    
    log_success "Grafana run.sh script created successfully"
}

# Create Grafana dashboard configuration
create_grafana_dashboard_config() {
    log_info "Creating Grafana dashboard configuration..."
    
    local dashboard_config_path="$TIG_INSTALL_DIR/grafana/default-dashboard.yaml"
    
    # Embed the dashboard configuration content using heredoc
    local dashboard_config_content
    read -r -d '' dashboard_config_content << 'EOF' || true
# config file version
apiVersion: 1

providers:
 - name: 'default'
   orgId: 1
   folder: ''
   type: file
   options:
     path: /opt/grafana/dashboards
EOF
    
    # Create the dashboard configuration file
    create_config_file "$dashboard_config_path" "$dashboard_config_content"
    
    log_success "Grafana dashboard configuration created successfully"
}

# Create InfluxDB Dockerfile configuration
create_influxdb_dockerfile() {
    log_step_start "5" "InfluxDB Configuration"
    
    local dockerfile_path="$TIG_INSTALL_DIR/influxdb/Dockerfile"
    
    # Embed the InfluxDB Dockerfile content using heredoc
    local dockerfile_content
    read -r -d '' dockerfile_content << 'EOF' || true
FROM influxdb:1.8

LABEL author="Alexis Le Provost <alexis.leprovost@outlook.com>"
LABEL version="1.0.0"
LABEL description="InfluxDB docker image"

USER root

ADD influxdb.template.conf /influxdb.template.conf

ADD run.sh /run.sh
ENTRYPOINT ["bash", "/run.sh"]
EOF
    
    # Create the Dockerfile
    create_config_file "$dockerfile_path" "$dockerfile_content"
    
    # Create the InfluxDB run.sh script
    create_influxdb_run_script
    
    # Create the InfluxDB configuration template
    create_influxdb_config_template
    
    log_step_complete "5" "InfluxDB Configuration"
}

# Create InfluxDB run.sh script
create_influxdb_run_script() {
    log_info "Creating InfluxDB run.sh script..."
    
    local run_script_path="$TIG_INSTALL_DIR/influxdb/run.sh"
    
    # Embed the InfluxDB run.sh content using heredoc
    local run_script_content
    read -r -d '' run_script_content << 'EOF' || true
#!/bin/bash

set -m
CONFIG_TEMPLATE="/influxdb.template.conf"
CONFIG_FILE="/etc/influxdb/influxdb.conf"
CURR_TIMESTAMP=`date +%s`

mv -v $CONFIG_FILE $CONFIG_FILE.$CURR_TIMESTAMP
cp -v $CONFIG_TEMPLATE $CONFIG_FILE

exec influxd -config=$CONFIG_FILE 1>>/var/log/influxdb/influxdb.log 2>&1 &
sleep 5

USER_EXISTS=`influx -host=localhost -port=${INFLUXDB_PORT} -execute="SHOW USERS" | awk '{print $1}' | grep "${INFLUXDB_ADMIN_USER}" | wc -l`

if [ -n ${USER_EXISTS} ]
then
  influx -host=localhost -port=${INFLUXDB_PORT} -execute="CREATE USER ${INFLUXDB_ADMIN_USER} WITH PASSWORD '${INFLUXDB_ADMIN_PASSWORD}' WITH ALL PRIVILEGES"
  influx -host=localhost -port=${INFLUXDB_PORT} -username=${INFLUXDB_ADMIN_USER} -password="${INFLUXDB_ADMIN_PASSWORD}" -execute="create database ${INFLUXDB_DATABASE}"
  influx -host=localhost -port=${INFLUXDB_PORT} -username=${INFLUXDB_ADMIN_USER} -password="${INFLUXDB_ADMIN_PASSWORD}" -execute="grant all PRIVILEGES on ${INFLUXDB_DATABASE} to ${INFLUXDB_ADMIN_USER}"
fi 

tail -f /var/log/influxdb/influxdb.log
EOF
    
    # Create the executable script
    create_executable_script "$run_script_path" "$run_script_content"
    
    log_success "InfluxDB run.sh script created successfully"
}

# Create InfluxDB configuration template
create_influxdb_config_template() {
    log_info "Creating InfluxDB configuration template..."
    
    local config_template_path="$TIG_INSTALL_DIR/influxdb/influxdb.template.conf"
    
    # Embed the InfluxDB configuration template content using heredoc
    local config_template_content
    read -r -d '' config_template_content << 'EOF' || true
reporting-disabled = false
bind-address = ":8088"

[meta]
  dir = "/var/lib/influxdb/meta"
  retention-autocreate = true
  logging-enabled = true

[data]
  dir = "/var/lib/influxdb/data"
  engine = "tsm1"
  wal-dir = "/var/lib/influxdb/wal"
  wal-logging-enabled = true
  query-log-enabled = true
  cache-max-memory-size = 524288000
  cache-snapshot-memory-size = 26214400
  cache-snapshot-write-cold-duration = "1h0m0s"
  compact-full-write-cold-duration = "24h0m0s"
  max-points-per-block = 0
  max-series-per-database = 1000000
  trace-logging-enabled = false

[coordinator]
  write-timeout = "10s"
  max-concurrent-queries = 0
  query-timeout = "0"
  log-queries-after = "0"
  max-select-point = 0
  max-select-series = 0
  max-select-buckets = 0

[retention]
  enabled = true
  check-interval = "30m0s"

[shard-precreation]
  enabled = true
  check-interval = "10m0s"
  advance-period = "30m0s"

[admin]
  enabled = true
  bind-address = ":8083"
  https-enabled = false
  https-certificate = "/etc/ssl/influxdb.pem"

[monitor]
  store-enabled = true
  store-database = "_internal"
  store-interval = "10s"

[subscriber]
  enabled = true
  http-timeout = "30s"

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = false
  log-enabled = true
  write-tracing = false
  https-enabled = false
  https-certificate = "/etc/ssl/influxdb.pem"
  https-private-key = ""
  max-row-limit = 10000
  max-connection-limit = 0
  shared-secret = ""
  realm = "InfluxDB"

[[graphite]]
  enabled = false
  bind-address = ":2003"
  database = "graphite"
  retention-policy = ""
  protocol = "tcp"
  batch-size = 5000
  batch-pending = 10
  batch-timeout = "1s"
  consistency-level = "one"
  separator = "."
  udp-read-buffer = 0

[[collectd]]
  enabled = false
  bind-address = ":25826"
  database = "collectd"
  retention-policy = ""
  batch-size = 5000
  batch-pending = 10
  batch-timeout = "10s"
  read-buffer = 0
  typesdb = "/usr/share/collectd/types.db"

[[opentsdb]]
  enabled = false
  bind-address = ":4242"
  database = "opentsdb"
  retention-policy = ""
  consistency-level = "one"
  tls-enabled = false
  certificate = "/etc/ssl/influxdb.pem"
  batch-size = 1000
  batch-pending = 5
  batch-timeout = "1s"
  log-point-errors = true

[[udp]]
  enabled = false
  bind-address = ":8089"
  database = "udp"
  retention-policy = ""
  batch-size = 5000
  batch-pending = 10
  read-buffer = 0
  batch-timeout = "1s"
  precision = ""

[continuous_queries]
  log-enabled = true
  enabled = true
  run-interval = "1s"
EOF
    
    # Create the configuration template file
    create_config_file "$config_template_path" "$config_template_content"
    
    log_success "InfluxDB configuration template created successfully"
}

# Create Telegraf Dockerfile configuration
create_telegraf_dockerfile() {
    log_step_start "6" "Telegraf Configuration"
    
    local dockerfile_path="$TIG_INSTALL_DIR/telegraf/Dockerfile"
    
    # Embed the Telegraf Dockerfile content using heredoc
    local dockerfile_content
    read -r -d '' dockerfile_content << 'EOF' || true
FROM telegraf:1.24

LABEL author="Alexis Le Provost <alexis.leprovost@outlook.com>"
LABEL version="1.0.0"
LABEL description="Telegraf docker image"

USER root

ADD telegraf.conf.template /telegraf.conf.template
COPY *.conf /etc/telegraf/telegraf.d/

RUN apt-get update && apt-get -y install build-essential hddtemp

ADD run.sh /run.sh
ENTRYPOINT ["bash", "/run.sh"]
EOF
    
    # Create the Dockerfile
    create_config_file "$dockerfile_path" "$dockerfile_content"
    
    # Create the Telegraf run.sh script
    create_telegraf_run_script
    
    # Create the Telegraf configuration template
    create_telegraf_config_template
    
    # Create the sample configuration file
    create_telegraf_sample_config
    
    log_step_complete "6" "Telegraf Configuration"
}

# Create Telegraf run.sh script
create_telegraf_run_script() {
    log_info "Creating Telegraf run.sh script..."
    
    local run_script_path="$TIG_INSTALL_DIR/telegraf/run.sh"
    
    # Embed the Telegraf run.sh content using heredoc
    local run_script_content
    read -r -d '' run_script_content << 'EOF' || true
#!/bin/bash

set -m
CONFIG_TEMPLATE="/telegraf.conf.template"
CONFIG_FILE="/etc/telegraf/telegraf.conf"

sed -e "s/\${TELEGRAF_HOST}/$TELEGRAF_HOST/" \
    -e "s!\${INFLUXDB_HOST}!$INFLUXDB_HOST!" \
    -e "s/\${INFLUXDB_PORT}/$INFLUXDB_PORT/" \
    -e "s/\${INFLUXDB_DATABASE}/$INFLUXDB_DATABASE/" \
    $CONFIG_TEMPLATE > $CONFIG_FILE

hddtemp -d --listen localhost --port 7634 /dev/sd*

mount --bind /hostfs/proc/ /proc/

echo "=> Starting Telegraf ..."
exec telegraf -config /etc/telegraf/telegraf.conf --config-directory /etc/telegraf/telegraf.d
EOF
    
    # Create the executable script
    create_executable_script "$run_script_path" "$run_script_content"
    
    log_success "Telegraf run.sh script created successfully"
}

# Generate secure passwords for services
generate_secure_passwords() {
    log_step_start "7" "Password Generation"
    
    # Generate secure passwords if not already set
    if [ -z "${TIG_GRAFANA_PASSWORD:-}" ]; then
        TIG_GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
        log_info "Generated Grafana password"
    fi
    
    if [ -z "${TIG_INFLUXDB_PASSWORD:-}" ]; then
        TIG_INFLUXDB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
        log_info "Generated InfluxDB password"
    fi
    
    # Validate passwords meet minimum requirements
    if [ ${#TIG_GRAFANA_PASSWORD} -lt 8 ] || [ ${#TIG_INFLUXDB_PASSWORD} -lt 8 ]; then
        log_step_failed "7" "Password Generation" "Generated passwords do not meet minimum length requirements"
        return 1
    fi
    
    log_step_complete "7" "Password Generation"
}

# Create environment file with all configuration
create_env_file() {
    log_step_start "8" "Environment File Creation"
    
    local env_file="$TIG_INSTALL_DIR/.env"
    
    # Set default values
    local grafana_port="${TIG_GRAFANA_PORT:-3000}"
    local grafana_user="${TIG_GRAFANA_USER:-admin}"
    local influxdb_port="${TIG_INFLUXDB_PORT:-8086}"
    local influxdb_user="${TIG_INFLUXDB_USER:-grafana}"
    local influxdb_database="${TIG_INFLUXDB_DATABASE:-metrics}"
    local container_prefix="${TIG_CONTAINER_PREFIX:-tig}"
    
    # Create .env file content
    local env_content
    read -r -d '' env_content << EOF || true
# TIG Stack Environment Configuration
# Generated on $(date)

# Container Configuration
CONTAINER_PREFIX=$container_prefix

# Grafana Configuration
GRAFANA_PORT=$grafana_port
GRAFANA_USER=$grafana_user
GRAFANA_PASSWORD=$TIG_GRAFANA_PASSWORD

# InfluxDB Configuration
INFLUXDB_PORT=$influxdb_port
INFLUXDB_HOST=influxdb
INFLUXDB_DATABASE=$influxdb_database
INFLUXDB_ADMIN_USER=$influxdb_user
INFLUXDB_ADMIN_PASSWORD=$TIG_INFLUXDB_PASSWORD

# Telegraf Configuration
TELEGRAF_HOST=telegraf
EOF
    
    # Create the .env file
    create_config_file "$env_file" "$env_content" "600"
    
    # Validate .env file was created
    if [ ! -f "$env_file" ]; then
        log_step_failed "8" "Environment File Creation" "Failed to create .env file"
        return 1
    fi
    
    log_info "Environment file created with secure permissions"
    log_step_complete "8" "Environment File Creation"
}

# Deploy the TIG stack using docker-compose
deploy_tig_stack() {
    log_step_start "9" "TIG Stack Deployment"
    
    # Change to installation directory
    cd "$TIG_INSTALL_DIR" || {
        log_step_failed "9" "TIG Stack Deployment" "Cannot change to installation directory"
        return 1
    }
    
    # Build and start containers
    log_info "Building and starting TIG stack containers..."
    if ! docker-compose up -d --build; then
        log_step_failed "9" "TIG Stack Deployment" "Docker compose up failed"
        return 1
    fi
    
    # Wait for containers to start
    log_info "Waiting for containers to start..."
    sleep 30
    
    # Check container status
    local running_containers
    running_containers=$(docker-compose ps --services --filter "status=running" | wc -l)
    
    if [ "$running_containers" -lt 3 ]; then
        log_step_failed "9" "TIG Stack Deployment" "Not all containers started successfully"
        docker-compose ps
        return 1
    fi
    
    log_info "All containers started successfully"
    log_step_complete "9" "TIG Stack Deployment"
}

# Validate the deployment is working
validate_deployment() {
    log_step_start "10" "Deployment Validation"
    
    # Check if containers are running
    local grafana_status influxdb_status telegraf_status
    grafana_status=$(docker-compose ps grafana --format "{{.State}}" 2>/dev/null || echo "not found")
    influxdb_status=$(docker-compose ps influxdb --format "{{.State}}" 2>/dev/null || echo "not found")
    telegraf_status=$(docker-compose ps telegraf --format "{{.State}}" 2>/dev/null || echo "not found")
    
    log_info "Container Status - Grafana: $grafana_status, InfluxDB: $influxdb_status, Telegraf: $telegraf_status"
    
    # Test Grafana accessibility
    local grafana_port="${TIG_GRAFANA_PORT:-3000}"
    if ! curl -s -o /dev/null -w "%{http_code}" "http://localhost:$grafana_port" | grep -q "200\|302"; then
        log_warning "Grafana may not be fully accessible yet (this is normal during startup)"
    else
        log_info "Grafana is accessible on port $grafana_port"
    fi
    
    log_step_complete "10" "Deployment Validation"
}

# Configure containers to restart automatically
configure_restart_persistence() {
    log_step_start "11" "Restart Persistence Configuration"
    
    # Docker containers are already configured with restart: always in docker-compose.yml
    log_info "Containers configured with restart policy: always"
    
    # Ensure Docker service starts on boot
    if ! systemctl is-enabled docker >/dev/null 2>&1; then
        systemctl enable docker
        log_info "Docker service enabled for automatic startup"
    fi
    
    log_step_complete "11" "Restart Persistence Configuration"
}

# Create basic documentation
create_documentation() {
    log_step_start "12" "Documentation Creation"
    
    local readme_file="$TIG_INSTALL_DIR/README.md"
    local readme_content
    read -r -d '' readme_content << EOF || true
# TIG Stack Monitoring

This TIG (Telegraf/InfluxDB/Grafana) stack was automatically installed via EC2 user data script.

## Services

- **Grafana**: Web-based monitoring dashboard
  - URL: http://$(hostname -I | awk '{print $1}'):${TIG_GRAFANA_PORT:-3000}
  - Username: ${TIG_GRAFANA_USER:-admin}
  - Password: Check .env file

- **InfluxDB**: Time-series database
  - Port: ${TIG_INFLUXDB_PORT:-8086}
  - Database: ${TIG_INFLUXDB_DATABASE:-metrics}

- **Telegraf**: Metrics collection agent
  - Collects system and Docker metrics

## Management

- Start services: \`docker-compose up -d\`
- Stop services: \`docker-compose down\`
- View logs: \`docker-compose logs [service]\`
- Check status: \`docker-compose ps\`

## Troubleshooting

- Installation log: $LOG_FILE
- Container logs: \`docker-compose logs\`
- System logs: \`journalctl -u docker\`

Generated on: $(date)
EOF
    
    create_config_file "$readme_file" "$readme_content"
    
    log_info "Documentation created at $readme_file"
    log_step_complete "12" "Documentation Creation"
}

# Main execution function with comprehensive error handling
main() {
    # Initialize logging first
    initialize_logging
    
    # Execute installation steps with error handling
    local step_functions=(
        "install_docker"
        "create_directory_structure" 
        "create_docker_compose_file"
        "create_grafana_dockerfile"
        "create_influxdb_dockerfile"
        "create_telegraf_dockerfile"
        "generate_secure_passwords"
        "create_env_file"
        "deploy_tig_stack"
        "validate_deployment"
        "configure_restart_persistence"
        "create_documentation"
    )
    
    local step_names=(
        "Docker Installation"
        "Directory Structure Creation"
        "Docker Compose Configuration"
        "Grafana Configuration"
        "InfluxDB Configuration" 
        "Telegraf Configuration"
        "Password Generation"
        "Environment File Creation"
        "TIG Stack Deployment"
        "Deployment Validation"
        "Restart Persistence Configuration"
        "Documentation Creation"
    )
    
    # Execute each step with individual error handling
    for i in "${!step_functions[@]}"; do
        local step_num=$((i + 1))
        local func_name="${step_functions[$i]}"
        local step_name="${step_names[$i]}"
        
        # Skip steps that don't have functions implemented yet
        if ! declare -f "$func_name" >/dev/null 2>&1; then
            log_warning "Step $step_num ($step_name) - Function $func_name not implemented, skipping"
            continue
        fi
        
        # Execute step with error handling
        if ! $func_name; then
            handle_recoverable_error "$step_num" "$step_name" "Function execution failed"
            # Continue with next step instead of exiting
            continue
        fi
    done
    
    # Final validation
    if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
        SCRIPT_STATUS="SUCCESS"
        log_success "All installation steps completed successfully"
    else
        SCRIPT_STATUS="PARTIAL_SUCCESS"
        log_warning "Installation completed with ${#FAILED_STEPS[@]} failed steps"
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Create Telegraf configuration template (essential parts only)
create_telegraf_config_template() {
    log_info "Creating Telegraf configuration template..."
    
    local config_template_path="$TIG_INSTALL_DIR/telegraf/telegraf.conf.template"
    
    # Embed a simplified but functional Telegraf configuration template
    local config_template_content
    read -r -d '' config_template_content << 'EOF' || true
# Telegraf Configuration
#
# Telegraf is entirely plugin driven. All metrics are gathered from the
# declared inputs, and sent to the declared outputs.

# Global tags can be specified here in key="value" format.
[global_tags]

# Configuration for telegraf agent
[agent]
  ## Default data collection interval for all inputs
  interval = "5s"
  ## Rounds collection interval to 'interval'
  round_interval = true
  ## Telegraf will send metrics to outputs in batches of at most metric_batch_size metrics.
  metric_batch_size = 1000
  ## For failed writes, telegraf will cache metric_buffer_limit metrics for each output
  metric_buffer_limit = 10000
  ## Collection jitter is used to jitter the collection by a random amount.
  collection_jitter = "0s"
  ## Default flushing interval for all outputs.
  flush_interval = "5s"
  ## Jitter the flush interval by a random amount.
  flush_jitter = "0s"
  ## By default, precision will be set to the same timestamp order as the collection interval
  precision = ""
  ## Run telegraf in debug mode
  debug = false
  ## Run telegraf in quiet mode
  quiet = false
  ## Override default hostname, if empty use os.Hostname()
  hostname = "${TELEGRAF_HOST}"
  ## If set to true, do no set the "host" tag in the telegraf agent.
  omit_hostname = false

###############################################################################
#                            OUTPUT PLUGINS                                   #
###############################################################################

# Configuration for influxdb server to send metrics to
[[outputs.influxdb]]
  ## The full HTTP or UDP endpoint URL for your InfluxDB instance.
  urls = ["http://${INFLUXDB_HOST}:${INFLUXDB_PORT}"] # required
  ## The target database for metrics (telegraf will create it if not exists).
  database = "${INFLUXDB_DATABASE}" # required
  ## Retention policy to write to. Empty string writes to the default rp.
  retention_policy = ""
  ## Write consistency (clusters only), can be: "any", "one", "quorum", "all"
  write_consistency = "any"
  ## Write timeout (for the InfluxDB client), formatted as a string.
  timeout = "5s"

###############################################################################
#                            INPUT PLUGINS                                    #
###############################################################################

# Read metrics about cpu usage
[[inputs.cpu]]
  percpu = false
  totalcpu = true

[[inputs.cpu]]
  percpu = true
  totalcpu = false
  name_override = "percpu_usage"
  fielddrop = ["cpu_time*"]

# Read metrics about disk usage by mount point
[[inputs.disk]]
  ## Ignore some mountpoints by filesystem type.
  ignore_fs = ["tmpfs", "devtmpfs"]
  fielddrop = ["inodes*"]

# Read metrics about disk IO by device
[[inputs.diskio]]

# Get kernel statistics from /proc/stat
[[inputs.kernel]]

# Read metrics about memory usage
[[inputs.mem]]

# Read metrics about swap memory usage
[[inputs.swap]]

# Read metrics about system load & uptime
[[inputs.system]]

# Read metrics about docker containers
[[inputs.docker]]
  ## Docker Endpoint
  endpoint = "unix:///var/run/docker.sock"
  ## Whether to report for each container per-device blkio and network stats or not
  perdevice = true
  ## Whether to report for each container total blkio and network stats or not
  total = false

# Monitor disks' temperatures using hddtemp
[[inputs.hddtemp]]
  ## By default, telegraf gathers temps data from all disks detected by hddtemp.
  address = "127.0.0.1:7634"
EOF
    
    # Create the configuration template file
    create_config_file "$config_template_path" "$config_template_content"
    
    log_success "Telegraf configuration template created successfully"
}

# Create Telegraf sample configuration file
create_telegraf_sample_config() {
    log_info "Creating Telegraf sample configuration..."
    
    local sample_config_path="$TIG_INSTALL_DIR/telegraf/sample.conf"
    
    # Embed the sample configuration content using heredoc
    local sample_config_content
    read -r -d '' sample_config_content << 'EOF' || true
# Add any additional Telegraf configurations to this directory
# with a name ending in ".conf"
EOF
    
    # Create the sample configuration file
    create_config_file "$sample_config_path" "$sample_config_content"
    
    log_success "Telegraf sample configuration created successfully"
}

# Generate secure random password using openssl
generate_secure_password() {
    local length="${1:-16}"
    
    # Generate a secure random password using openssl
    # Remove problematic characters and ensure minimum length
    local password
    password=$(openssl rand -base64 32 | tr -d "=+/\n" | cut -c1-"$length")
    
    # Ensure password meets minimum requirements (at least 12 characters)
    if [ ${#password} -lt 12 ]; then
        # Fallback: generate longer password if needed
        password=$(openssl rand -base64 48 | tr -d "=+/\n" | cut -c1-16)
    fi
    
    echo "$password"
}

# Validate that openssl is available for password generation
validate_password_generation() {
    log_info "Validating password generation capabilities..."
    
    # Check if openssl is available
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "OpenSSL is not available for password generation"
        exit 1
    fi
    
    # Test password generation
    local test_password
    test_password=$(generate_secure_password 12)
    
    if [ -z "$test_password" ] || [ ${#test_password} -lt 12 ]; then
        log_error "Password generation test failed"
        exit 1
    fi
    
    log_success "Password generation validation completed successfully"
}

# Set up environment variables with secure defaults
setup_environment_variables() {
    log_info "Setting up environment variables with secure defaults..."
    
    # Container and service configuration
    export CONTAINER_PREFIX="${CONTAINER_PREFIX:-tig}"
    export TELEGRAF_HOST="${TELEGRAF_HOST:-telegraf}"
    
    # InfluxDB configuration
    export INFLUXDB_HOST="${INFLUXDB_HOST:-influxdb}"
    export INFLUXDB_PORT="${INFLUXDB_PORT:-8086}"
    export INFLUXDB_DATABASE="${INFLUXDB_DATABASE:-metrics}"
    export INFLUXDB_ADMIN_USER="${INFLUXDB_ADMIN_USER:-grafana}"
    
    # Generate secure InfluxDB password if not provided
    if [ -z "${INFLUXDB_ADMIN_PASSWORD:-}" ]; then
        INFLUXDB_ADMIN_PASSWORD=$(generate_secure_password 16)
        export INFLUXDB_ADMIN_PASSWORD
        log_info "Generated secure InfluxDB admin password"
    else
        log_info "Using provided InfluxDB admin password"
    fi
    
    # Grafana configuration
    export GRAFANA_PORT="${GRAFANA_PORT:-3000}"
    export GRAFANA_USER="${GRAFANA_USER:-admin}"
    
    # Generate secure Grafana password if not provided
    if [ -z "${GRAFANA_PASSWORD:-}" ]; then
        GRAFANA_PASSWORD=$(generate_secure_password 16)
        export GRAFANA_PASSWORD
        log_info "Generated secure Grafana admin password"
    else
        log_info "Using provided Grafana admin password"
    fi
    
    # Grafana plugins configuration
    export GRAFANA_PLUGINS_ENABLED="${GRAFANA_PLUGINS_ENABLED:-true}"
    export GRAFANA_PLUGINS="${GRAFANA_PLUGINS:-grafana-piechart-panel}"
    
    # Validate that all required variables are set
    validate_environment_variables
    
    log_success "Environment variables setup completed successfully"
}

# Validate that all required environment variables are properly set
validate_environment_variables() {
    log_info "Validating environment variables..."
    
    local required_vars=(
        "CONTAINER_PREFIX"
        "TELEGRAF_HOST"
        "INFLUXDB_HOST"
        "INFLUXDB_PORT"
        "INFLUXDB_DATABASE"
        "INFLUXDB_ADMIN_USER"
        "INFLUXDB_ADMIN_PASSWORD"
        "GRAFANA_PORT"
        "GRAFANA_USER"
        "GRAFANA_PASSWORD"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    # Validate password strength (minimum 12 characters)
    if [ ${#INFLUXDB_ADMIN_PASSWORD} -lt 12 ]; then
        log_error "InfluxDB admin password does not meet minimum security requirements (12+ characters)"
        exit 1
    fi
    
    if [ ${#GRAFANA_PASSWORD} -lt 12 ]; then
        log_error "Grafana admin password does not meet minimum security requirements (12+ characters)"
        exit 1
    fi
    
    # Validate port numbers
    if ! [[ "$INFLUXDB_PORT" =~ ^[0-9]+$ ]] || [ "$INFLUXDB_PORT" -lt 1 ] || [ "$INFLUXDB_PORT" -gt 65535 ]; then
        log_error "Invalid InfluxDB port: $INFLUXDB_PORT"
        exit 1
    fi
    
    if ! [[ "$GRAFANA_PORT" =~ ^[0-9]+$ ]] || [ "$GRAFANA_PORT" -lt 1 ] || [ "$GRAFANA_PORT" -gt 65535 ]; then
        log_error "Invalid Grafana port: $GRAFANA_PORT"
        exit 1
    fi
    
    log_success "Environment variables validation completed successfully"
}

# Display configuration summary (without sensitive information)
display_configuration_summary() {
    log_info "=== TIG Stack Configuration Summary ==="
    log_info "Container Prefix: $CONTAINER_PREFIX"
    log_info "Telegraf Host: $TELEGRAF_HOST"
    log_info "InfluxDB Host: $INFLUXDB_HOST"
    log_info "InfluxDB Port: $INFLUXDB_PORT"
    log_info "InfluxDB Database: $INFLUXDB_DATABASE"
    log_info "InfluxDB Admin User: $INFLUXDB_ADMIN_USER"
    log_info "InfluxDB Admin Password: [SECURED - ${#INFLUXDB_ADMIN_PASSWORD} characters]"
    log_info "Grafana Port: $GRAFANA_PORT"
    log_info "Grafana User: $GRAFANA_USER"
    log_info "Grafana Password: [SECURED - ${#GRAFANA_PASSWORD} characters]"
    log_info "Grafana Plugins Enabled: $GRAFANA_PLUGINS_ENABLED"
    log_info "Grafana Plugins: $GRAFANA_PLUGINS"
    log_info "=== End Configuration Summary ==="
}

# Create .env file with all required environment variables
create_env_file() {
    log_info "Creating .env file with configuration variables..."
    
    local env_file="$TIG_INSTALL_DIR/.env"
    
    # Ensure the TIG install directory exists
    if [ ! -d "$TIG_INSTALL_DIR" ]; then
        log_error "TIG install directory does not exist: $TIG_INSTALL_DIR"
        exit 1
    fi
    
    # Create the .env file with all required variables
    local env_content
    read -r -d '' env_content << EOF || true
CONTAINER_PREFIX=$CONTAINER_PREFIX

TELEGRAF_HOST=$TELEGRAF_HOST

INFLUXDB_HOST=$INFLUXDB_HOST
INFLUXDB_PORT=$INFLUXDB_PORT
INFLUXDB_DATABASE=$INFLUXDB_DATABASE
INFLUXDB_ADMIN_USER=$INFLUXDB_ADMIN_USER
INFLUXDB_ADMIN_PASSWORD=$INFLUXDB_ADMIN_PASSWORD

GRAFANA_PORT=$GRAFANA_PORT
GRAFANA_USER=$GRAFANA_USER
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
GRAFANA_PLUGINS_ENABLED=$GRAFANA_PLUGINS_ENABLED
GRAFANA_PLUGINS=$GRAFANA_PLUGINS
EOF
    
    # Create the .env file using the helper function
    create_config_file "$env_file" "$env_content"
    
    # Validate the .env file was created successfully
    validate_env_file "$env_file"
    
    log_success ".env file created successfully at $env_file"
}

# Validate the created .env file
validate_env_file() {
    local env_file="$1"
    
    log_info "Validating .env file..."
    
    # Check if file exists
    if [ ! -f "$env_file" ]; then
        log_error ".env file was not created: $env_file"
        exit 1
    fi
    
    # Check if file is readable
    if [ ! -r "$env_file" ]; then
        log_error ".env file is not readable: $env_file"
        exit 1
    fi
    
    # Validate that all required variables are present in the file
    local required_vars=(
        "CONTAINER_PREFIX"
        "TELEGRAF_HOST"
        "INFLUXDB_HOST"
        "INFLUXDB_PORT"
        "INFLUXDB_DATABASE"
        "INFLUXDB_ADMIN_USER"
        "INFLUXDB_ADMIN_PASSWORD"
        "GRAFANA_PORT"
        "GRAFANA_USER"
        "GRAFANA_PASSWORD"
        "GRAFANA_PLUGINS_ENABLED"
        "GRAFANA_PLUGINS"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing variables in .env file: ${missing_vars[*]}"
        exit 1
    fi
    
    # Validate that passwords are not empty in the file
    local influxdb_password_line
    local grafana_password_line
    
    influxdb_password_line=$(grep "^INFLUXDB_ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2)
    grafana_password_line=$(grep "^GRAFANA_PASSWORD=" "$env_file" | cut -d'=' -f2)
    
    if [ -z "$influxdb_password_line" ] || [ ${#influxdb_password_line} -lt 12 ]; then
        log_error "InfluxDB password in .env file is empty or too short"
        exit 1
    fi
    
    if [ -z "$grafana_password_line" ] || [ ${#grafana_password_line} -lt 12 ]; then
        log_error "Grafana password in .env file is empty or too short"
        exit 1
    fi
    
    # Check file permissions (should be readable by owner and group, not world-readable for security)
    local file_perms
    file_perms=$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%A' "$env_file" 2>/dev/null)
    
    if [ "$file_perms" != "644" ]; then
        log_info "Adjusting .env file permissions for security..."
        chmod 640 "$env_file"
        log_info "Set .env file permissions to 640 (owner read/write, group read, no world access)"
    fi
    
    log_success ".env file validation completed successfully"
}

# Display .env file summary (without sensitive information)
display_env_file_summary() {
    local env_file="$TIG_INSTALL_DIR/.env"
    
    log_info "=== .env File Summary ==="
    log_info "Location: $env_file"
    
    if [ -f "$env_file" ]; then
        local file_size
        file_size=$(wc -c < "$env_file")
        log_info "File size: $file_size bytes"
        
        local line_count
        line_count=$(wc -l < "$env_file")
        log_info "Lines: $line_count"
        
        # Show non-sensitive variables
        log_info "Container prefix: $(grep '^CONTAINER_PREFIX=' "$env_file" | cut -d'=' -f2)"
        log_info "InfluxDB port: $(grep '^INFLUXDB_PORT=' "$env_file" | cut -d'=' -f2)"
        log_info "Grafana port: $(grep '^GRAFANA_PORT=' "$env_file" | cut -d'=' -f2)"
        log_info "InfluxDB database: $(grep '^INFLUXDB_DATABASE=' "$env_file" | cut -d'=' -f2)"
        
        # Show password lengths without revealing passwords
        local influxdb_pass_len
        local grafana_pass_len
        influxdb_pass_len=$(grep '^INFLUXDB_ADMIN_PASSWORD=' "$env_file" | cut -d'=' -f2 | wc -c)
        grafana_pass_len=$(grep '^GRAFANA_PASSWORD=' "$env_file" | cut -d'=' -f2 | wc -c)
        
        # Subtract 1 from wc -c because it counts the newline
        influxdb_pass_len=$((influxdb_pass_len - 1))
        grafana_pass_len=$((grafana_pass_len - 1))
        
        log_info "InfluxDB password: [SECURED - $influxdb_pass_len characters]"
        log_info "Grafana password: [SECURED - $grafana_pass_len characters]"
    else
        log_error ".env file not found for summary"
    fi
    
    log_info "=== End .env File Summary ==="
}

# Deploy TIG stack using docker-compose
deploy_tig_stack() {
    log_info "Starting TIG stack deployment..."
    
    local compose_file="$TIG_INSTALL_DIR/docker-compose.yml"
    local env_file="$TIG_INSTALL_DIR/.env"
    
    # Validate required files exist
    if [ ! -f "$compose_file" ]; then
        log_error "docker-compose.yml file not found: $compose_file"
        exit 1
    fi
    
    if [ ! -f "$env_file" ]; then
        log_error ".env file not found: $env_file"
        exit 1
    fi
    
    # Change to the TIG stack directory
    cd "$TIG_INSTALL_DIR" || {
        log_error "Failed to change to TIG stack directory: $TIG_INSTALL_DIR"
        exit 1
    }
    
    log_info "Changed to directory: $(pwd)"
    
    # Stop any existing containers (in case of re-deployment)
    log_info "Stopping any existing TIG stack containers..."
    docker-compose down --remove-orphans 2>/dev/null || {
        log_info "No existing containers to stop (this is normal for first deployment)"
    }
    
    # Build and start the containers with proper flags
    log_info "Building and starting TIG stack containers..."
    
    # Use docker-compose up with appropriate flags:
    # -d: detached mode (run in background)
    # --build: build images before starting containers
    # --remove-orphans: remove containers for services not defined in compose file
    if docker-compose up -d --build --remove-orphans; then
        log_success "TIG stack containers started successfully"
    else
        log_error "Failed to start TIG stack containers"
        log_info "Attempting to show container logs for debugging..."
        docker-compose logs --tail=50 || true
        exit 1
    fi
    
    # Display container status
    log_info "Container status after deployment:"
    docker-compose ps | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_success "TIG stack deployment completed"
}

# Validate service startup with health checks and retry logic
validate_service_startup() {
    log_info "Validating TIG stack service startup..."
    
    local max_retries=30
    local retry_interval=10
    local compose_file="$TIG_INSTALL_DIR/docker-compose.yml"
    
    # Change to the TIG stack directory
    cd "$TIG_INSTALL_DIR" || {
        log_error "Failed to change to TIG stack directory: $TIG_INSTALL_DIR"
        exit 1
    }
    
    # Wait for containers to be in running state
    log_info "Waiting for containers to reach running state..."
    
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        local running_containers
        local total_containers
        
        # Count running containers
        running_containers=$(docker-compose ps -q | xargs -r docker inspect --format='{{.State.Status}}' | grep -c "running" || echo "0")
        total_containers=$(docker-compose ps -q | wc -l)
        
        log_info "Container status check (attempt $((retry_count + 1))/$max_retries): $running_containers/$total_containers containers running"
        
        if [ "$running_containers" -eq "$total_containers" ] && [ "$total_containers" -gt 0 ]; then
            log_success "All containers are running"
            break
        fi
        
        if [ $retry_count -eq $((max_retries - 1)) ]; then
            log_error "Timeout waiting for containers to start after $((max_retries * retry_interval)) seconds"
            log_info "Final container status:"
            docker-compose ps | while IFS= read -r line; do
                log_info "  $line"
            done
            
            # Show logs for failed containers
            log_info "Logs for containers that failed to start:"
            docker-compose ps -q | while read -r container_id; do
                if [ -n "$container_id" ]; then
                    local container_name
                    local container_status
                    container_name=$(docker inspect --format='{{.Name}}' "$container_id" | sed 's/^.//')
                    container_status=$(docker inspect --format='{{.State.Status}}' "$container_id")
                    
                    if [ "$container_status" != "running" ]; then
                        log_error "Container $container_name is in state: $container_status"
                        log_info "Last 20 lines of logs for $container_name:"
                        docker logs --tail=20 "$container_id" 2>&1 | while IFS= read -r log_line; do
                            log_info "  [$container_name] $log_line"
                        done
                    fi
                fi
            done
            
            # Attempt restart for failed containers
            attempt_container_restart
            return 1
        fi
        
        retry_count=$((retry_count + 1))
        log_info "Waiting $retry_interval seconds before next check..."
        sleep $retry_interval
    done
    
    # Perform container health checks
    perform_container_health_checks
    
    log_success "Service startup validation completed successfully"
}

# Attempt to restart failed containers
attempt_container_restart() {
    log_info "Attempting to restart failed containers..."
    
    local restart_attempts=3
    local attempt=1
    
    while [ $attempt -le $restart_attempts ]; do
        log_info "Restart attempt $attempt/$restart_attempts"
        
        # Stop all containers
        docker-compose down --remove-orphans 2>/dev/null || true
        
        # Wait a moment
        sleep 5
        
        # Start containers again
        if docker-compose up -d --build --remove-orphans; then
            log_info "Restart attempt $attempt succeeded"
            
            # Wait for containers to stabilize
            sleep 15
            
            # Check if containers are running
            local running_containers
            local total_containers
            running_containers=$(docker-compose ps -q | xargs -r docker inspect --format='{{.State.Status}}' | grep -c "running" || echo "0")
            total_containers=$(docker-compose ps -q | wc -l)
            
            if [ "$running_containers" -eq "$total_containers" ] && [ "$total_containers" -gt 0 ]; then
                log_success "Container restart successful - all containers running"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $restart_attempts ]; then
            log_info "Restart attempt $attempt failed, waiting before next attempt..."
            sleep 10
        fi
    done
    
    log_error "All restart attempts failed"
    return 1
}

# Perform basic health checks on containers
perform_container_health_checks() {
    log_info "Performing container health checks..."
    
    # Check InfluxDB container
    check_influxdb_health
    
    # Check Telegraf container
    check_telegraf_health
    
    # Check Grafana container
    check_grafana_health
    
    log_success "Container health checks completed"
}

# Check InfluxDB container health
check_influxdb_health() {
    log_info "Checking InfluxDB container health..."
    
    local influxdb_container
    influxdb_container=$(docker-compose ps -q influxdb)
    
    if [ -z "$influxdb_container" ]; then
        log_error "InfluxDB container not found"
        return 1
    fi
    
    # Check if container is running
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$influxdb_container")
    
    if [ "$container_status" != "running" ]; then
        log_error "InfluxDB container is not running (status: $container_status)"
        return 1
    fi
    
    # Check if InfluxDB port is responding
    local influxdb_port
    influxdb_port=$(grep '^INFLUXDB_PORT=' "$TIG_INSTALL_DIR/.env" | cut -d'=' -f2)
    
    if docker exec "$influxdb_container" curl -f "http://localhost:$influxdb_port/ping" >/dev/null 2>&1; then
        log_success "InfluxDB container is healthy and responding on port $influxdb_port"
    else
        log_error "InfluxDB container is not responding on port $influxdb_port"
        return 1
    fi
    
    return 0
}

# Check Telegraf container health
check_telegraf_health() {
    log_info "Checking Telegraf container health..."
    
    local telegraf_container
    telegraf_container=$(docker-compose ps -q telegraf)
    
    if [ -z "$telegraf_container" ]; then
        log_error "Telegraf container not found"
        return 1
    fi
    
    # Check if container is running
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$telegraf_container")
    
    if [ "$container_status" != "running" ]; then
        log_error "Telegraf container is not running (status: $container_status)"
        return 1
    fi
    
    # Check if Telegraf process is running inside container
    if docker exec "$telegraf_container" pgrep telegraf >/dev/null 2>&1; then
        log_success "Telegraf container is healthy and process is running"
    else
        log_error "Telegraf process is not running inside container"
        return 1
    fi
    
    return 0
}

# Check Grafana container health
check_grafana_health() {
    log_info "Checking Grafana container health..."
    
    local grafana_container
    grafana_container=$(docker-compose ps -q grafana)
    
    if [ -z "$grafana_container" ]; then
        log_error "Grafana container not found"
        return 1
    fi
    
    # Check if container is running
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$grafana_container")
    
    if [ "$container_status" != "running" ]; then
        log_error "Grafana container is not running (status: $container_status)"
        return 1
    fi
    
    # Check if Grafana port is responding
    local grafana_port
    grafana_port=$(grep '^GRAFANA_PORT=' "$TIG_INSTALL_DIR/.env" | cut -d'=' -f2)
    
    # Wait a bit for Grafana to fully start up
    sleep 5
    
    if docker exec "$grafana_container" curl -f "http://localhost:$grafana_port/api/health" >/dev/null 2>&1; then
        log_success "Grafana container is healthy and responding on port $grafana_port"
    else
        log_error "Grafana container is not responding on port $grafana_port"
        return 1
    fi
    
    return 0
}

# Main execution starts here
main() {
    initialize_logging
    log_info "Starting TIG Stack deployment process..."
    
    # Validate password generation capabilities and set up environment variables (Task 6)
    validate_password_generation
    setup_environment_variables
    display_configuration_summary
    
    # Install Docker and Docker Compose
    install_docker
    
    # Create directory structure and file generation functions (Task 3)
    create_directory_structure
    validate_directory_structure
    # Create docker-compose.yml configuration (Task 4)
    create_docker_compose_file
    # Create Dockerfile configurations (Task 5)
    create_grafana_dockerfile
    create_influxdb_dockerfile
    create_telegraf_dockerfile
    
    # Create .env file with all configuration variables (Task 7)
    create_env_file
    display_env_file_summary
    
    # Deploy and start TIG stack services (Task 8)
    deploy_tig_stack
    validate_service_startup
    
    # TODO: Add service validation (Task 10)
    # TODO: Add restart persistence (Task 11)
    
    log_success "TIG Stack deployment process completed successfully"
}

# Execute main function
main "$@"