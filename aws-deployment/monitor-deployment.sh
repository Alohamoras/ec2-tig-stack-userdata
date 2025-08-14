#!/bin/bash

# Monitor TIG Stack deployment progress on c5.4xlarge instance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if instance details file exists
if [ ! -f "instance-details.txt" ]; then
    echo -e "${RED}Error: instance-details.txt not found. Please run launch-instance.sh first.${NC}"
    exit 1
fi

# Extract instance details
PUBLIC_IP=$(grep "Public IP:" instance-details.txt | cut -d' ' -f3)
INSTANCE_ID=$(grep "Instance ID:" instance-details.txt | cut -d' ' -f3)
KEY_NAME="IAD-Key"  # Replace with your key pair name

echo -e "${GREEN}=== TIG Stack Deployment Monitor ===${NC}"
echo -e "Instance ID: ${BLUE}$INSTANCE_ID${NC}"
echo -e "Public IP: ${BLUE}$PUBLIC_IP${NC}"
echo ""

# Function to run SSH command
run_ssh_command() {
    local command="$1"
    local description="$2"
    
    echo -e "${YELLOW}$description${NC}"
    ssh -i $KEY_NAME.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$PUBLIC_IP "$command" 2>/dev/null || echo -e "${RED}Command failed or instance not ready${NC}"
    echo ""
}

# Function to check if SSH is available
check_ssh_connectivity() {
    echo -e "${YELLOW}Checking SSH connectivity...${NC}"
    if ssh -i $KEY_NAME.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$PUBLIC_IP "echo 'SSH connection successful'" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH connection established${NC}"
        return 0
    else
        echo -e "${RED}✗ SSH connection failed${NC}"
        return 1
    fi
}

# Function to monitor deployment progress
monitor_deployment() {
    echo -e "${GREEN}=== Deployment Progress Monitor ===${NC}"
    
    # Check deployment start
    run_ssh_command "cat /tmp/tig-deployment-start.txt 2>/dev/null || echo 'Deployment not started yet'" "Deployment Start Status:"
    
    # Check installation log (last 20 lines)
    run_ssh_command "tail -20 /var/log/tig-stack-install.log 2>/dev/null || echo 'Installation log not available yet'" "Recent Installation Log:"
    
    # Check Docker status
    run_ssh_command "systemctl is-active docker 2>/dev/null || echo 'Docker not installed/started yet'" "Docker Status:"
    
    # Check containers
    run_ssh_command "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo 'Docker containers not running yet'" "Container Status:"
    
    # Check system resources (simplified to avoid awk issues)
    run_ssh_command "echo 'Memory Usage:'; free -h | grep '^Mem:' || echo 'Memory info not available'; echo 'Disk Usage:'; df -h / | tail -1 || echo 'Disk info not available'; echo 'Load Average:'; uptime || echo 'Load info not available'" "System Resources:"
    
    # Check deployment completion
    run_ssh_command "cat /tmp/tig-deployment-complete.txt 2>/dev/null || echo 'Deployment not completed yet'" "Deployment Completion Status:"
    
    # Test Grafana accessibility
    echo -e "${YELLOW}Testing Grafana accessibility...${NC}"
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://$PUBLIC_IP:3000 | grep -q "200\|302"; then
        echo -e "${GREEN}✓ Grafana is accessible at http://$PUBLIC_IP:3000${NC}"
    else
        echo -e "${RED}✗ Grafana is not accessible yet${NC}"
    fi
    echo ""
}

# Function to show access information
show_access_info() {
    echo -e "${GREEN}=== Access Information ===${NC}"
    echo -e "Grafana URL: ${BLUE}http://$PUBLIC_IP:3000${NC}"
    echo -e "InfluxDB URL: ${BLUE}http://$PUBLIC_IP:8086${NC}"
    echo -e "SSH Command: ${BLUE}ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP${NC}"
    echo ""
    echo -e "${YELLOW}Default Grafana Credentials:${NC}"
    echo -e "Username: ${BLUE}admin${NC}"
    echo -e "Password: ${BLUE}Check /opt/tig-stack/.env file on the instance${NC}"
    echo ""
}

# Function to run continuous monitoring
continuous_monitor() {
    echo -e "${GREEN}Starting continuous monitoring (Press Ctrl+C to stop)...${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${GREEN}=== TIG Stack Deployment Monitor - $(date) ===${NC}"
        echo -e "Instance: ${BLUE}$INSTANCE_ID${NC} | IP: ${BLUE}$PUBLIC_IP${NC}"
        echo ""
        
        if check_ssh_connectivity; then
            monitor_deployment
            show_access_info
        else
            echo -e "${YELLOW}Waiting for instance to be ready...${NC}"
        fi
        
        echo -e "${YELLOW}Refreshing in 30 seconds... (Press Ctrl+C to stop)${NC}"
        sleep 30
    done
}

# Main menu
echo -e "${YELLOW}Choose monitoring option:${NC}"
echo "1. One-time status check"
echo "2. Continuous monitoring"
echo "3. Show access information only"
echo "4. Check installation logs"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        if check_ssh_connectivity; then
            monitor_deployment
            show_access_info
        fi
        ;;
    2)
        continuous_monitor
        ;;
    3)
        show_access_info
        ;;
    4)
        if check_ssh_connectivity; then
            echo -e "${YELLOW}Installation logs (last 50 lines):${NC}"
            run_ssh_command "tail -50 /var/log/tig-stack-install.log 2>/dev/null || echo 'Log file not available yet'" "Installation Log:"
        fi
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac