#!/bin/bash

# Self-contained TIG Stack User Data for c5.4xlarge Testing
# This version doesn't download from GitHub to avoid BASH_SOURCE issues

# Exit on error, but don't use -u (nounset) to avoid BASH_SOURCE issues
set -eo pipefail

# Custom environment variables for large instance testing
export TIG_GRAFANA_PORT=3000
export TIG_GRAFANA_USER=admin
export TIG_GRAFANA_PASSWORD="TigTest$(date +%s)!"
export TIG_INFLUXDB_PORT=8086
export CONTAINER_PREFIX=test-tig
export TELEGRAF_INTERVAL=10s
export TELEGRAF_HOSTNAME="c5-4xlarge-test-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# Performance optimizations for large instance
export DOCKER_OPTS="--storage-driver=overlay2 --log-driver=json-file --log-opt max-size=10m --log-opt max-file=3"

# Enable detailed logging for testing
export LOG_FILE="/var/log/tig-stack-install.log"
export DEBUG=true

# Script variables and directory paths
readonly SCRIPT_NAME="tig-stack-installer"
readonly TIG_INSTALL_DIR="/opt/tig-stack"
readonly TIG_USER="ec2-user"

# Global status tracking
SCRIPT_STATUS="RUNNING"
FAILED_STEPS=()
COMPLETED_STEPS=()
TOTAL_STEPS=12

# Create a test marker file
echo "TIG Stack deployment started at $(date)" > /tmp/tig-deployment-start.txt
echo "Instance Type: c5.4xlarge" >> /tmp/tig-deployment-start.txt
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" >> /tmp/tig-deployment-start.txt
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)" >> /tmp/tig-deployment-start.txt

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

# Enhanced logging initialization
initialize_logging() {
    # Create log file with proper permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log_info "=== TIG Stack Installation Started ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "Version: 1.0.0"
    log_info "Log file: $LOG_FILE"
    log_info "Install directory: $TIG_INSTALL_DIR"
    log_info "Target user: $TIG_USER"
    log_info "Process ID: $$"
    log_info "Total steps: $TOTAL_STEPS"
    
    # Log system information
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
        log_step_complete "1" "Docker Installation (already installed)"
        return 0
    fi
    
    case "$OS" in
        "amzn"|"amazon")
            # Update package manager
            yum update -y
            # Install Docker
            yum install -y docker
            # Start and enable Docker service
            systemctl start docker
            systemctl enable docker
            ;;
        "ubuntu")
            # Update package index
            apt-get update
            # Install prerequisites
            apt-get install -y ca-certificates curl gnupg lsb-release
            # Add Docker's official GPG key
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            # Set up the repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            # Update package index again
            apt-get update
            # Install Docker Engine
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            # Start and enable Docker service
            systemctl start docker
            systemctl enable docker
            ;;
        *)
            log_step_failed "1" "Docker Installation" "Unsupported operating system: $OS"
            return 1
            ;;
    esac
    
    # Configure Docker service and user permissions
    if ! getent group docker > /dev/null 2>&1; then
        groupadd docker
    fi
    
    if id "$TIG_USER" >/dev/null 2>&1; then
        usermod -aG docker "$TIG_USER"
    fi
    
    # Install Docker Compose
    local compose_version="v2.24.1"
    curl -L "https://github.com/docker/compose/releases/download/$compose_version/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
    
    log_step_complete "1" "Docker Installation"
}

# Create TIG stack directory structure
create_directory_structure() {
    log_step_start "2" "Directory Structure Creation"
    
    # Create main installation directory
    mkdir -p "$TIG_INSTALL_DIR"
    
    # Create service directories
    local service_dirs=("grafana" "influxdb" "telegraf")
    for dir in "${service_dirs[@]}"; do
        mkdir -p "$TIG_INSTALL_DIR/$dir"
    done
    
    # Set proper ownership
    if id "$TIG_USER" >/dev/null 2>&1; then
        chown -R "$TIG_USER:$TIG_USER" "$TIG_INSTALL_DIR"
    fi
    
    chmod -R 755 "$TIG_INSTALL_DIR"
    
    log_step_complete "2" "Directory Structure Creation"
}

# Create environment file
create_env_file() {
    log_step_start "3" "Environment Configuration"
    
    local env_file="$TIG_INSTALL_DIR/.env"
    
    cat > "$env_file" << EOF
CONTAINER_PREFIX=$CONTAINER_PREFIX

TELEGRAF_HOST=telegraf
TELEGRAF_HOSTNAME=$TELEGRAF_HOSTNAME

INFLUXDB_HOST=influxdb
INFLUXDB_PORT=$TIG_INFLUXDB_PORT
INFLUXDB_DATABASE=telegraf
INFLUXDB_ADMIN_USER=grafana
INFLUXDB_ADMIN_PASSWORD=$TIG_GRAFANA_PASSWORD

GRAFANA_PORT=$TIG_GRAFANA_PORT
GRAFANA_USER=$TIG_GRAFANA_USER
GRAFANA_PASSWORD=$TIG_GRAFANA_PASSWORD
GRAFANA_PLUGINS_ENABLED=true
GRAFANA_PLUGINS=grafana-piechart-panel
EOF
    
    chown "$TIG_USER:$TIG_USER" "$env_file"
    chmod 644 "$env_file"
    
    log_step_complete "3" "Environment Configuration"
}

# Create docker-compose.yml
create_docker_compose() {
    log_step_start "4" "Docker Compose Configuration"
    
    local compose_file="$TIG_INSTALL_DIR/docker-compose.yml"
    
    cat > "$compose_file" << 'EOF'
version: "3"

services:
    influxdb:
        image: influxdb:1.8
        container_name: ${CONTAINER_PREFIX}_influxdb
        ports:
            - ${INFLUXDB_PORT}:8086
        volumes:
            - influxdb-data:/var/lib/influxdb
        restart: always
        environment:
            - INFLUXDB_DB=${INFLUXDB_DATABASE}
            - INFLUXDB_ADMIN_USER=${INFLUXDB_ADMIN_USER}
            - INFLUXDB_ADMIN_PASSWORD=${INFLUXDB_ADMIN_PASSWORD}
        networks:
            - tig-network

    telegraf:
        image: telegraf:1.28
        container_name: ${CONTAINER_PREFIX}_telegraf
        depends_on:
            - influxdb
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /proc:/hostfs/proc:ro
            - /sys:/hostfs/sys:ro
            - /etc:/hostfs/etc:ro
        privileged: true
        restart: always
        environment:
            - HOST_PROC=/hostfs/proc
            - HOST_SYS=/hostfs/sys
            - HOST_ETC=/hostfs/etc
            - TELEGRAF_HOSTNAME=${TELEGRAF_HOSTNAME}
            - INFLUXDB_DATABASE=${INFLUXDB_DATABASE}
            - INFLUXDB_ADMIN_USER=${INFLUXDB_ADMIN_USER}
            - INFLUXDB_ADMIN_PASSWORD=${INFLUXDB_ADMIN_PASSWORD}
        networks:
            - tig-network
            
    grafana:
        image: grafana/grafana:10.2.0
        container_name: ${CONTAINER_PREFIX}_grafana
        ports: 
            - ${GRAFANA_PORT}:3000
        depends_on:
            - influxdb
        volumes:
            - grafana-data:/var/lib/grafana
        restart: always
        environment:
            - GF_SECURITY_ADMIN_USER=${GRAFANA_USER}
            - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
            - GF_INSTALL_PLUGINS=grafana-piechart-panel
        networks:
            - tig-network

volumes:
    influxdb-data:
    grafana-data:

networks:
    tig-network:
        driver: bridge
EOF
    
    chown "$TIG_USER:$TIG_USER" "$compose_file"
    chmod 644 "$compose_file"
    
    log_step_complete "4" "Docker Compose Configuration"
}

# Deploy TIG stack
deploy_tig_stack() {
    log_step_start "5" "TIG Stack Deployment"
    
    cd "$TIG_INSTALL_DIR"
    
    # Pull images first
    docker-compose pull
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be ready
    sleep 30
    
    # Check if containers are running
    if docker-compose ps | grep -q "Up"; then
        log_success "TIG Stack containers are running"
    else
        log_error "TIG Stack containers failed to start"
        docker-compose logs
        return 1
    fi
    
    log_step_complete "5" "TIG Stack Deployment"
}

# Main function
main() {
    initialize_logging
    
    install_docker || exit 1
    create_directory_structure || exit 1
    create_env_file || exit 1
    create_docker_compose || exit 1
    deploy_tig_stack || exit 1
    
    log_success "TIG Stack installation completed successfully!"
    log_info "Grafana should be accessible at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):$TIG_GRAFANA_PORT"
    log_info "Default credentials - User: $TIG_GRAFANA_USER, Password: $TIG_GRAFANA_PASSWORD"
    
    # Create completion marker
    echo "TIG Stack deployment completed at $(date)" > /tmp/tig-deployment-complete.txt
    echo "Total deployment time: $(($(date +%s) - $(stat -c %Y /tmp/tig-deployment-start.txt))) seconds" >> /tmp/tig-deployment-complete.txt
}

# Execute main function
main "$@"