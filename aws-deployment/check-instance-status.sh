#!/bin/bash

# Comprehensive EC2 instance status checker for TIG Stack deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TIG Stack Instance Status Checker ===${NC}"

# Check if instance details file exists
if [ ! -f "instance-details.txt" ]; then
    echo -e "${RED}Error: instance-details.txt not found.${NC}"
    echo -e "${YELLOW}Please provide the instance details manually:${NC}"
    read -p "Enter Instance ID: " INSTANCE_ID
    read -p "Enter AWS Region: " REGION
    read -p "Enter Public IP (if known): " PUBLIC_IP
else
    # Extract instance details
    INSTANCE_ID=$(grep "Instance ID:" instance-details.txt | cut -d' ' -f3)
    REGION=$(grep "Region:" instance-details.txt | cut -d' ' -f2)
    PUBLIC_IP=$(grep "Public IP:" instance-details.txt | cut -d' ' -f3)
fi

echo -e "Instance ID: ${BLUE}$INSTANCE_ID${NC}"
echo -e "Region: ${BLUE}$REGION${NC}"
echo -e "Public IP: ${BLUE}$PUBLIC_IP${NC}"
echo ""

# Function to get detailed instance information
get_instance_info() {
    aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'Reservations[0].Instances[0].[State.Name,LaunchTime,InstanceType,PublicIpAddress,PrivateIpAddress]' \
        --output text 2>/dev/null
}

# Function to get status checks
get_detailed_status() {
    aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --include-all-instances \
        --query 'InstanceStatuses[0]' \
        --output json 2>/dev/null
}

# Get instance information
echo -e "${YELLOW}Getting instance information...${NC}"
INSTANCE_INFO=$(get_instance_info)

if [ -n "$INSTANCE_INFO" ]; then
    STATE=$(echo "$INSTANCE_INFO" | awk '{print $1}')
    LAUNCH_TIME=$(echo "$INSTANCE_INFO" | awk '{print $2}')
    INSTANCE_TYPE=$(echo "$INSTANCE_INFO" | awk '{print $3}')
    CURRENT_PUBLIC_IP=$(echo "$INSTANCE_INFO" | awk '{print $4}')
    PRIVATE_IP=$(echo "$INSTANCE_INFO" | awk '{print $5}')
    
    echo -e "${GREEN}=== Instance Details ===${NC}"
    echo -e "State: ${BLUE}$STATE${NC}"
    echo -e "Launch Time: ${BLUE}$LAUNCH_TIME${NC}"
    echo -e "Instance Type: ${BLUE}$INSTANCE_TYPE${NC}"
    echo -e "Public IP: ${BLUE}$CURRENT_PUBLIC_IP${NC}"
    echo -e "Private IP: ${BLUE}$PRIVATE_IP${NC}"
    
    # Calculate uptime
    if [ "$LAUNCH_TIME" != "None" ] && [ -n "$LAUNCH_TIME" ]; then
        LAUNCH_TIMESTAMP=$(date -d "$LAUNCH_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAUNCH_TIME%.*}" +%s 2>/dev/null || echo "0")
        CURRENT_TIMESTAMP=$(date +%s)
        UPTIME_SECONDS=$((CURRENT_TIMESTAMP - LAUNCH_TIMESTAMP))
        UPTIME_MINUTES=$((UPTIME_SECONDS / 60))
        echo -e "Uptime: ${BLUE}${UPTIME_MINUTES} minutes (${UPTIME_SECONDS} seconds)${NC}"
    fi
    echo ""
else
    echo -e "${RED}Could not retrieve instance information${NC}"
    exit 1
fi

# Get detailed status
echo -e "${YELLOW}Getting status checks...${NC}"
STATUS_JSON=$(get_detailed_status)

if [ "$STATUS_JSON" != "null" ] && [ -n "$STATUS_JSON" ]; then
    SYSTEM_STATUS=$(echo "$STATUS_JSON" | jq -r '.SystemStatus.Status // "not-available"')
    INSTANCE_STATUS=$(echo "$STATUS_JSON" | jq -r '.InstanceStatus.Status // "not-available"')
    
    echo -e "${GREEN}=== Status Checks ===${NC}"
    echo -e "System Status: ${BLUE}$SYSTEM_STATUS${NC}"
    echo -e "Instance Status: ${BLUE}$INSTANCE_STATUS${NC}"
    
    # Show detailed status check results
    if [ "$STATUS_JSON" != "null" ]; then
        echo ""
        echo -e "${YELLOW}Detailed Status Check Results:${NC}"
        echo "$STATUS_JSON" | jq -r '.SystemStatus.Details[]? | "System - \(.Name): \(.Status)"' 2>/dev/null || echo "No system status details available"
        echo "$STATUS_JSON" | jq -r '.InstanceStatus.Details[]? | "Instance - \(.Name): \(.Status)"' 2>/dev/null || echo "No instance status details available"
    fi
else
    echo -e "${YELLOW}Status checks not available yet${NC}"
fi
echo ""

# Check network connectivity
echo -e "${YELLOW}Testing network connectivity...${NC}"
if [ "$CURRENT_PUBLIC_IP" != "None" ] && [ -n "$CURRENT_PUBLIC_IP" ]; then
    echo -e "Testing ping to ${BLUE}$CURRENT_PUBLIC_IP${NC}..."
    if ping -c 3 -W 3 "$CURRENT_PUBLIC_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Instance is reachable via ping${NC}"
    else
        echo -e "${RED}✗ Instance is not responding to ping${NC}"
        echo -e "${YELLOW}  This is normal during boot process${NC}"
    fi
    
    # Test SSH port
    echo -e "Testing SSH connectivity to ${BLUE}$CURRENT_PUBLIC_IP:22${NC}..."
    if timeout 5 bash -c "</dev/tcp/$CURRENT_PUBLIC_IP/22" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH port (22) is open${NC}"
    else
        echo -e "${RED}✗ SSH port (22) is not accessible yet${NC}"
        echo -e "${YELLOW}  SSH typically becomes available 2-3 minutes after launch${NC}"
    fi
    
    # Test Grafana port
    echo -e "Testing Grafana port ${BLUE}$CURRENT_PUBLIC_IP:3000${NC}..."
    if timeout 5 bash -c "</dev/tcp/$CURRENT_PUBLIC_IP/3000" 2>/dev/null; then
        echo -e "${GREEN}✓ Grafana port (3000) is open - TIG Stack is likely ready!${NC}"
    else
        echo -e "${YELLOW}○ Grafana port (3000) not accessible yet${NC}"
        echo -e "${YELLOW}  TIG Stack deployment typically takes 5-8 minutes total${NC}"
    fi
else
    echo -e "${RED}No public IP available for connectivity testing${NC}"
fi
echo ""

# Provide timeline and next steps
echo -e "${GREEN}=== Deployment Timeline ===${NC}"
echo -e "${YELLOW}Expected Timeline for c5.4xlarge:${NC}"
echo "• 0-2 min: Instance launching (pending → running)"
echo "• 2-3 min: Status checks initializing → ok"
echo "• 3-4 min: SSH becomes available"
echo "• 3-5 min: User data script starts TIG installation"
echo "• 5-8 min: TIG Stack fully deployed and accessible"
echo ""

# Determine current phase and provide guidance
if [ "$STATE" = "pending" ]; then
    echo -e "${YELLOW}Current Phase: Instance Launching${NC}"
    echo "• Wait 1-2 more minutes for instance to reach 'running' state"
    echo "• Re-run this script to check progress"
elif [ "$STATE" = "running" ] && [ "$SYSTEM_STATUS" != "ok" ]; then
    echo -e "${YELLOW}Current Phase: Status Checks Initializing${NC}"
    echo "• Instance is running but status checks not complete"
    echo "• This is normal, wait 1-2 more minutes"
elif [ "$STATE" = "running" ] && [ "$SYSTEM_STATUS" = "ok" ] && [ "$INSTANCE_STATUS" != "ok" ]; then
    echo -e "${YELLOW}Current Phase: Instance Status Check Pending${NC}"
    echo "• System is healthy, instance status check in progress"
    echo "• Wait 1-2 more minutes"
elif [ "$STATE" = "running" ] && [ "$SYSTEM_STATUS" = "ok" ] && [ "$INSTANCE_STATUS" = "ok" ]; then
    echo -e "${GREEN}Current Phase: Instance Ready - User Data Executing${NC}"
    echo "• Instance is fully ready, TIG Stack installation in progress"
    echo "• Check serial console logs: ./check-serial-logs.sh"
    echo "• Monitor deployment: ./monitor-deployment.sh"
    echo "• TIG Stack should be ready in 2-5 more minutes"
else
    echo -e "${RED}Current Phase: Unknown State${NC}"
    echo "• Check AWS console for any issues"
    echo "• Review serial console logs: ./check-serial-logs.sh"
fi

echo ""
echo -e "${BLUE}Available Commands:${NC}"
echo -e "• Check serial logs: ${YELLOW}./check-serial-logs.sh${NC}"
echo -e "• Monitor deployment: ${YELLOW}./monitor-deployment.sh${NC}"
echo -e "• Re-run status check: ${YELLOW}./check-instance-status.sh${NC}"

if [ "$CURRENT_PUBLIC_IP" != "None" ] && [ -n "$CURRENT_PUBLIC_IP" ]; then
    echo ""
    echo -e "${BLUE}Access Information (when ready):${NC}"
    echo -e "• Grafana: ${YELLOW}http://$CURRENT_PUBLIC_IP:3000${NC}"
    echo -e "• SSH: ${YELLOW}ssh -i your-key.pem ec2-user@$CURRENT_PUBLIC_IP${NC}"
fi