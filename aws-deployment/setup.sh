#!/bin/bash

# Setup script for TIG Stack deployment
# This script helps configure your key pair and other settings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TIG Stack Deployment Setup ===${NC}"
echo ""

# Function to update KEY_NAME in scripts
update_key_name() {
    local key_name="$1"
    
    # Update launch-instance.sh
    sed -i.bak "s/KEY_NAME=\".*\"/KEY_NAME=\"$key_name\"/" launch-instance.sh
    
    # Update monitor-deployment.sh
    sed -i.bak "s/KEY_NAME=\".*\"/KEY_NAME=\"$key_name\"/" monitor-deployment.sh
    
    # Remove backup files
    rm -f *.bak
    
    echo -e "${GREEN}✓ Updated KEY_NAME to '$key_name' in scripts${NC}"
}

# Function to update region
update_region() {
    local region="$1"
    
    # Update launch-instance.sh
    sed -i.bak "s/REGION=\".*\"/REGION=\"$region\"/" launch-instance.sh
    
    # Remove backup files
    rm -f *.bak
    
    echo -e "${GREEN}✓ Updated REGION to '$region' in launch-instance.sh${NC}"
}

# Check if AWS CLI is configured
echo -e "${YELLOW}Checking AWS CLI configuration...${NC}"
if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_REGION=$(aws configure get region || echo "not-set")
    echo -e "${GREEN}✓ AWS CLI is configured${NC}"
    echo -e "Account ID: ${BLUE}$ACCOUNT_ID${NC}"
    echo -e "Default Region: ${BLUE}$CURRENT_REGION${NC}"
else
    echo -e "${RED}✗ AWS CLI is not configured${NC}"
    echo -e "${YELLOW}Please run 'aws configure' first${NC}"
    exit 1
fi
echo ""

# Get key pair name
echo -e "${YELLOW}Step 1: Configure EC2 Key Pair${NC}"
echo ""
echo "Available key pairs in your account:"
aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output table 2>/dev/null || echo "No key pairs found or error accessing EC2"
echo ""

read -p "Enter your EC2 key pair name (without .pem extension): " KEY_NAME
if [ -z "$KEY_NAME" ]; then
    echo -e "${RED}Error: Key pair name cannot be empty${NC}"
    exit 1
fi

# Check if key pair exists
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Key pair '$KEY_NAME' exists in AWS${NC}"
else
    echo -e "${RED}✗ Key pair '$KEY_NAME' not found in AWS${NC}"
    echo -e "${YELLOW}Please create the key pair first or use an existing one${NC}"
    exit 1
fi

# Update scripts with key name
update_key_name "$KEY_NAME"
echo ""

# Configure region
echo -e "${YELLOW}Step 2: Configure AWS Region${NC}"
if [ "$CURRENT_REGION" != "not-set" ]; then
    read -p "Use current region ($CURRENT_REGION)? [Y/n]: " use_current_region
    if [[ $use_current_region =~ ^[Nn]$ ]]; then
        read -p "Enter AWS region: " REGION
        update_region "$REGION"
    else
        update_region "$CURRENT_REGION"
    fi
else
    read -p "Enter AWS region (e.g., us-east-1): " REGION
    update_region "$REGION"
fi
echo ""

# Key file placement options
echo -e "${YELLOW}Step 3: Key File Placement${NC}"
echo ""
echo "You have several options for your key file:"
echo ""
echo -e "${BLUE}Option 1 (Recommended): Place in aws-deployment directory${NC}"
echo "  - Copy your key file here: aws-deployment/$KEY_NAME.pem"
echo "  - Command: cp ~/Downloads/$KEY_NAME.pem ./"
echo "  - Set permissions: chmod 400 $KEY_NAME.pem"
echo ""
echo -e "${BLUE}Option 2: Use from ~/.ssh directory${NC}"
echo "  - Place key file: ~/.ssh/$KEY_NAME.pem"
echo "  - Scripts will automatically find it there"
echo ""
echo -e "${BLUE}Option 3: Use absolute path${NC}"
echo "  - Keep key file anywhere"
echo "  - Update scripts to use full path"
echo ""

read -p "Which option do you prefer? (1/2/3): " key_option

case $key_option in
    1)
        echo -e "${YELLOW}Please copy your key file to this directory:${NC}"
        echo -e "${BLUE}cp ~/Downloads/$KEY_NAME.pem ./aws-deployment/${NC}"
        echo -e "${BLUE}chmod 400 ./aws-deployment/$KEY_NAME.pem${NC}"
        echo ""
        read -p "Press Enter when you've copied the key file..."
        
        if [ -f "$KEY_NAME.pem" ]; then
            chmod 400 "$KEY_NAME.pem"
            echo -e "${GREEN}✓ Key file found and permissions set${NC}"
        else
            echo -e "${RED}✗ Key file not found. Please copy it and run setup again.${NC}"
            exit 1
        fi
        ;;
    2)
        echo -e "${YELLOW}Please ensure your key file is at:${NC}"
        echo -e "${BLUE}~/.ssh/$KEY_NAME.pem${NC}"
        echo ""
        # Update scripts to use ~/.ssh path
        sed -i.bak "s/-i \$KEY_NAME\.pem/-i ~\/.ssh\/\$KEY_NAME.pem/g" launch-instance.sh monitor-deployment.sh
        rm -f *.bak
        echo -e "${GREEN}✓ Scripts updated to use ~/.ssh directory${NC}"
        ;;
    3)
        read -p "Enter full path to your key file: " KEY_PATH
        if [ -f "$KEY_PATH" ]; then
            # Update scripts to use absolute path
            sed -i.bak "s/-i \$KEY_NAME\.pem/-i $KEY_PATH/g" launch-instance.sh monitor-deployment.sh
            rm -f *.bak
            echo -e "${GREEN}✓ Scripts updated to use absolute path${NC}"
        else
            echo -e "${RED}✗ Key file not found at $KEY_PATH${NC}"
            exit 1
        fi
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac
echo ""

# Final verification
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo -e "Key Pair: ${BLUE}$KEY_NAME${NC}"
echo -e "Region: ${BLUE}$(grep 'REGION=' launch-instance.sh | cut -d'"' -f2)${NC}"
echo -e "Account: ${BLUE}$ACCOUNT_ID${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Run: ${BLUE}./launch-instance.sh${NC}"
echo -e "2. Monitor: ${BLUE}./monitor-deployment.sh${NC}"
echo -e "3. Clean up: ${BLUE}./cleanup.sh${NC}"
echo ""
echo -e "${GREEN}Ready to deploy! 🚀${NC}"