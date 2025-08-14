#!/bin/bash

# Cleanup script for TIG Stack testing resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TIG Stack Testing Cleanup ===${NC}"

# Check if instance details file exists
if [ ! -f "instance-details.txt" ]; then
    echo -e "${RED}Error: instance-details.txt not found. No resources to clean up.${NC}"
    exit 1
fi

# Extract details
INSTANCE_ID=$(grep "Instance ID:" instance-details.txt | cut -d' ' -f3)
STACK_NAME=$(grep "CloudFormation Stack:" instance-details.txt | cut -d' ' -f3)
REGION=$(grep "Region:" instance-details.txt | cut -d' ' -f2)

echo -e "Instance ID: ${YELLOW}$INSTANCE_ID${NC}"
echo -e "CloudFormation Stack: ${YELLOW}$STACK_NAME${NC}"
echo -e "Region: ${YELLOW}$REGION${NC}"
echo ""

# Confirmation
read -p "Are you sure you want to delete these resources? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

# Terminate instance
echo -e "${YELLOW}Terminating instance...${NC}"
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION

echo -e "${YELLOW}Waiting for instance termination...${NC}"
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION

echo -e "${GREEN}✓ Instance terminated${NC}"

# Delete CloudFormation stack (this will delete the security group)
echo -e "${YELLOW}Deleting CloudFormation stack...${NC}"
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION

echo -e "${YELLOW}Waiting for stack deletion...${NC}"
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION

echo -e "${GREEN}✓ CloudFormation stack deleted${NC}"

# Clean up local files
echo -e "${YELLOW}Cleaning up local files...${NC}"
rm -f instance-details.txt

echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo -e "All AWS resources have been deleted."
echo -e "Local instance details file has been removed."