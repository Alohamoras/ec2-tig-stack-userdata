#!/bin/bash

# Launch c5.4xlarge instance with TIG Stack for testing
# Make sure to configure your AWS CLI and have appropriate permissions

set -e

# Configuration
INSTANCE_TYPE="c5.4xlarge"
KEY_NAME="IAD-Key"  # Replace with your key pair name
SECURITY_GROUP_NAME="tig-stack-testing-sg"
REGION="us-east-1"  # Change to your preferred region

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TIG Stack c5.4xlarge Instance Launch ===${NC}"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}Error: AWS CLI not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

# Get the default VPC ID
echo -e "${YELLOW}Getting default VPC...${NC}"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo -e "${RED}Error: No default VPC found. Please specify a VPC ID.${NC}"
    exit 1
fi
echo -e "${GREEN}Using VPC: $VPC_ID${NC}"

# Create security group using CloudFormation
echo -e "${YELLOW}Creating security group...${NC}"
STACK_NAME="tig-stack-testing-sg-$(date +%s)"
aws cloudformation create-stack \
    --stack-name $STACK_NAME \
    --template-body file://security-group.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=$VPC_ID \
    --region $REGION

echo -e "${YELLOW}Waiting for security group creation...${NC}"
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION

# Get security group ID
SECURITY_GROUP_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' \
    --output text --region $REGION)

echo -e "${GREEN}Security Group created: $SECURITY_GROUP_ID${NC}"

# Get the latest Amazon Linux 2 AMI
echo -e "${YELLOW}Getting latest Amazon Linux 2 AMI...${NC}"
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text --region $REGION)

echo -e "${GREEN}Using AMI: $AMI_ID${NC}"

# Get default subnet
echo -e "${YELLOW}Getting default subnet...${NC}"
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" \
    --query 'Subnets[0].SubnetId' \
    --output text --region $REGION)

echo -e "${GREEN}Using Subnet: $SUBNET_ID${NC}"

# Launch instance
echo -e "${YELLOW}Launching c5.4xlarge instance...${NC}"
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --subnet-id $SUBNET_ID \
    --user-data file://user-data-c5-4xlarge.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=TIG-Stack-Testing-c5.4xlarge},{Key=Purpose,Value=TIG-Stack-Testing},{Key=Environment,Value=Testing}]' \
    --associate-public-ip-address \
    --query 'Instances[0].InstanceId' \
    --output text --region $REGION)

echo -e "${GREEN}Instance launched: $INSTANCE_ID${NC}"

# Wait for instance to be running
echo -e "${YELLOW}Waiting for instance to be running...${NC}"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# Get instance details
INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress,State.Name]' \
    --output text --region $REGION)

PUBLIC_IP=$(echo $INSTANCE_INFO | awk '{print $1}')
PRIVATE_IP=$(echo $INSTANCE_INFO | awk '{print $2}')
STATE=$(echo $INSTANCE_INFO | awk '{print $3}')

echo -e "${GREEN}=== Instance Details ===${NC}"
echo -e "Instance ID: ${GREEN}$INSTANCE_ID${NC}"
echo -e "Instance Type: ${GREEN}$INSTANCE_TYPE${NC}"
echo -e "Public IP: ${GREEN}$PUBLIC_IP${NC}"
echo -e "Private IP: ${GREEN}$PRIVATE_IP${NC}"
echo -e "State: ${GREEN}$STATE${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

echo -e "${GREEN}=== Access Information ===${NC}"
echo -e "SSH Command: ${YELLOW}ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP${NC}"
echo -e "Grafana URL: ${YELLOW}http://$PUBLIC_IP:3000${NC}"
echo -e "InfluxDB URL: ${YELLOW}http://$PUBLIC_IP:8086${NC}"

echo -e "${GREEN}=== Monitoring Commands ===${NC}"
echo -e "Check installation logs: ${YELLOW}ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP 'tail -f /var/log/tig-stack-install.log'${NC}"
echo -e "Check deployment status: ${YELLOW}ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP 'cat /tmp/tig-deployment-*.txt'${NC}"
echo -e "Check containers: ${YELLOW}ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP 'docker ps'${NC}"

echo -e "${GREEN}=== Next Steps ===${NC}"
echo -e "1. Wait 3-5 minutes for TIG stack installation to complete"
echo -e "2. Access Grafana at: http://$PUBLIC_IP:3000"
echo -e "3. Default login: admin / (check /opt/tig-stack/.env for password)"
echo -e "4. Monitor installation progress with the commands above"

# Save instance details for later reference
cat > instance-details.txt << EOF
Instance ID: $INSTANCE_ID
Instance Type: $INSTANCE_TYPE
Public IP: $PUBLIC_IP
Private IP: $PRIVATE_IP
Region: $REGION
Security Group: $SECURITY_GROUP_ID
CloudFormation Stack: $STACK_NAME
Launch Time: $(date)

SSH Command: ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP
Grafana URL: http://$PUBLIC_IP:3000
InfluxDB URL: http://$PUBLIC_IP:8086

Monitoring Commands:
- tail -f /var/log/tig-stack-install.log
- cat /tmp/tig-deployment-*.txt
- docker ps
- systemctl status docker
EOF

echo -e "${GREEN}Instance details saved to: instance-details.txt${NC}"