#!/bin/bash

# Check EC2 instance serial console logs for TIG Stack deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== EC2 Instance Serial Console Logs ===${NC}"

# Check if instance details file exists
if [ ! -f "instance-details.txt" ]; then
    echo -e "${RED}Error: instance-details.txt not found.${NC}"
    echo -e "${YELLOW}Please provide the instance ID manually:${NC}"
    read -p "Enter Instance ID: " INSTANCE_ID
    read -p "Enter AWS Region: " REGION
else
    # Extract instance details
    INSTANCE_ID=$(grep "Instance ID:" instance-details.txt | cut -d' ' -f3)
    REGION=$(grep "Region:" instance-details.txt | cut -d' ' -f2)
fi

echo -e "Instance ID: ${BLUE}$INSTANCE_ID${NC}"
echo -e "Region: ${BLUE}$REGION${NC}"
echo ""

# Function to get instance state
get_instance_state() {
    aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown"
}

# Function to get instance status checks
get_status_checks() {
    aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
        --output text 2>/dev/null || echo "not-available not-available"
}

# Check current instance state
INSTANCE_STATE=$(get_instance_state)
echo -e "${YELLOW}Current Instance State:${NC} $INSTANCE_STATE"

# Check status checks
STATUS_CHECKS=$(get_status_checks)
SYSTEM_STATUS=$(echo $STATUS_CHECKS | awk '{print $1}')
INSTANCE_STATUS=$(echo $STATUS_CHECKS | awk '{print $2}')

echo -e "${YELLOW}System Status Check:${NC} $SYSTEM_STATUS"
echo -e "${YELLOW}Instance Status Check:${NC} $INSTANCE_STATUS"
echo ""

# Get serial console output
echo -e "${YELLOW}Fetching serial console output...${NC}"
echo -e "${BLUE}==================== SERIAL CONSOLE OUTPUT ====================${NC}"

# Get the console output
CONSOLE_OUTPUT_RAW=$(aws ec2 get-console-output \
    --instance-id $INSTANCE_ID \
    --region $REGION \
    --output json 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$CONSOLE_OUTPUT_RAW" ]; then
    echo -e "${RED}Failed to retrieve console output${NC}"
    echo -e "${YELLOW}This could mean:${NC}"
    echo "• Console output not available yet (normal for new instances)"
    echo "• AWS CLI permissions issue"
    echo "• Instance is still initializing"
else
    CONSOLE_OUTPUT=$(echo "$CONSOLE_OUTPUT_RAW" | jq -r '.Output // empty')
    
    if [ -z "$CONSOLE_OUTPUT" ] || [ "$CONSOLE_OUTPUT" = "null" ]; then
        echo -e "${RED}No console output available yet.${NC}"
        echo -e "${YELLOW}This is normal for instances that just launched.${NC}"
        echo -e "${YELLOW}Console output typically appears 2-3 minutes after launch.${NC}"
    else
        # Decode and display the output (it's base64 encoded)
        echo "$CONSOLE_OUTPUT" | base64 -d 2>/dev/null || {
            echo -e "${RED}Error decoding console output${NC}"
            echo -e "${YELLOW}Raw output (first 1000 chars):${NC}"
            echo "$CONSOLE_OUTPUT" | head -c 1000
        }
    fi
fi

echo -e "${BLUE}==================== END SERIAL CONSOLE OUTPUT ====================${NC}"
echo ""

# Check if we can see cloud-init logs specifically
echo -e "${YELLOW}Looking for cloud-init related messages...${NC}"
if [ -n "$CONSOLE_OUTPUT" ] && [ "$CONSOLE_OUTPUT" != "null" ]; then
    DECODED_OUTPUT=$(echo "$CONSOLE_OUTPUT" | base64 -d 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$DECODED_OUTPUT" ]; then
        echo "$DECODED_OUTPUT" | grep -i "cloud-init\|user-data\|tig-stack" || echo "No cloud-init messages found yet"
    else
        echo "Could not decode console output for searching"
    fi
else
    echo "Console output not available yet"
fi
echo ""

# Provide troubleshooting information
echo -e "${GREEN}=== Troubleshooting Information ===${NC}"
echo -e "${YELLOW}Instance Launch Timeline:${NC}"
echo "1. Instance State: pending → running (1-2 minutes)"
echo "2. Status Checks: initializing → ok (2-3 minutes)"
echo "3. Console Output: Available (2-3 minutes)"
echo "4. User Data Execution: Starts after boot (3-4 minutes)"
echo "5. TIG Stack Ready: Complete deployment (5-8 minutes total)"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
if [ "$INSTANCE_STATE" = "pending" ]; then
    echo "• Instance is still launching, wait 1-2 more minutes"
elif [ "$INSTANCE_STATE" = "running" ] && [ "$INSTANCE_STATUS" != "ok" ]; then
    echo "• Instance is running but status checks not complete"
    echo "• Wait for status checks to pass"
elif [ "$CONSOLE_OUTPUT" = "None" ] || [ -z "$CONSOLE_OUTPUT" ]; then
    echo "• Console output not available yet, wait 1-2 more minutes"
    echo "• Run this script again in a few minutes"
else
    echo "• Console output is available, check for errors above"
    echo "• Look for cloud-init and user-data execution messages"
    echo "• If no TIG-related messages, user data may still be running"
fi

echo ""
echo -e "${BLUE}Re-run this script: ./check-serial-logs.sh${NC}"
echo -e "${BLUE}Monitor deployment: ./monitor-deployment.sh${NC}"