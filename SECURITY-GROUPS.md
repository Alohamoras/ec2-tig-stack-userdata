# EC2 Security Group Configuration for TIG Stack

This document provides detailed security group configuration requirements for the TIG Stack monitoring solution.

## Overview

The TIG Stack requires specific network access to function properly. This guide covers the minimum required security group rules and optional configurations for different use cases.

## Required Security Group Rules

### Inbound Rules (Minimum Required)

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | Your IP/CIDR | Grafana web interface access |

### Outbound Rules (Required for Installation)

| Type | Protocol | Port Range | Destination | Description |
|------|----------|------------|-------------|-------------|
| HTTPS | TCP | 443 | 0.0.0.0/0 | Package downloads and Docker Hub |
| HTTP | TCP | 80 | 0.0.0.0/0 | Package repository access |
| DNS | UDP | 53 | 0.0.0.0/0 | Domain name resolution |

## Security Group Templates

### Basic Configuration (Recommended)

```json
{
  "GroupName": "tig-stack-basic",
  "Description": "Basic security group for TIG Stack monitoring",
  "SecurityGroupRules": [
    {
      "IpPermissions": [
        {
          "IpProtocol": "tcp",
          "FromPort": 3000,
          "ToPort": 3000,
          "IpRanges": [
            {
              "CidrIp": "YOUR_IP/32",
              "Description": "Grafana web interface"
            }
          ]
        }
      ]
    }
  ]
}
```

### Development Configuration

For development environments where you need broader access:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | Your IP/32 | Instance management |
| Custom TCP | TCP | 3000 | Your IP/32 | Grafana web interface |
| Custom TCP | TCP | 8086 | Your IP/32 | InfluxDB API (optional) |

### Production Configuration

For production environments with restricted access:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | VPC CIDR | Grafana (internal access only) |
| SSH | TCP | 22 | Bastion SG | SSH through bastion host |

## Port Details

### Grafana (Port 3000)
- **Purpose**: Web interface for dashboards and administration
- **Required**: Yes
- **External Access**: Required for users to access dashboards
- **Security**: Should be restricted to trusted IP ranges

### InfluxDB (Port 8086)
- **Purpose**: Database API and administration
- **Required**: No (internal communication only)
- **External Access**: Not recommended for security
- **Security**: Only expose if external applications need direct database access

### Telegraf
- **Purpose**: Metrics collection agent
- **Ports**: No external ports required
- **Communication**: Internal to InfluxDB only

## Security Best Practices

### 1. Principle of Least Privilege
- Only open ports that are absolutely necessary
- Restrict source IP ranges to the minimum required
- Use specific CIDR blocks instead of 0.0.0.0/0 when possible

### 2. Source IP Restrictions
```bash
# Find your current IP
curl -s http://checkip.amazonaws.com

# Use specific IP ranges
# Office network: 203.0.113.0/24
# Home IP: 198.51.100.1/32
# VPN range: 192.0.2.0/24
```

### 3. Network Segmentation
- Place monitoring instances in private subnets when possible
- Use Application Load Balancer for external access
- Implement VPC endpoints for AWS services

### 4. Regular Security Reviews
- Audit security group rules monthly
- Remove unused rules and IP ranges
- Monitor CloudTrail for security group changes

## Advanced Configurations

### Load Balancer Integration

When using an Application Load Balancer:

#### ALB Security Group
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| HTTPS | TCP | 443 | 0.0.0.0/0 | Public HTTPS access |
| HTTP | TCP | 80 | 0.0.0.0/0 | HTTP redirect to HTTPS |

#### Instance Security Group
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | ALB-SG | Grafana from load balancer |

### VPC Peering Configuration

For cross-VPC monitoring:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | Peer VPC CIDR | Cross-VPC Grafana access |

### Multi-AZ Deployment

For high availability across multiple availability zones:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | VPC CIDR | Internal Grafana access |
| Custom TCP | TCP | 8086 | VPC CIDR | InfluxDB cluster communication |

## CloudFormation Template

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Security Group for TIG Stack Monitoring'

Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC ID where the security group will be created
  
  AllowedCidr:
    Type: String
    Default: '0.0.0.0/0'
    Description: CIDR block allowed to access Grafana
    
Resources:
  TigStackSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: tig-stack-monitoring
      GroupDescription: Security group for TIG Stack monitoring solution
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 3000
          ToPort: 3000
          CidrIp: !Ref AllowedCidr
          Description: Grafana web interface
      SecurityGroupEgress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          Description: HTTPS outbound
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
          Description: HTTP outbound
        - IpProtocol: udp
          FromPort: 53
          ToPort: 53
          CidrIp: 0.0.0.0/0
          Description: DNS resolution
      Tags:
        - Key: Name
          Value: tig-stack-monitoring
        - Key: Purpose
          Value: Monitoring

Outputs:
  SecurityGroupId:
    Description: Security Group ID for TIG Stack
    Value: !Ref TigStackSecurityGroup
    Export:
      Name: !Sub '${AWS::StackName}-SecurityGroupId'
```

## Terraform Configuration

```hcl
resource "aws_security_group" "tig_stack" {
  name_prefix = "tig-stack-"
  description = "Security group for TIG Stack monitoring"
  vpc_id      = var.vpc_id

  ingress {
    description = "Grafana web interface"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "tig-stack-monitoring"
    Purpose = "Monitoring"
  }
}

variable "vpc_id" {
  description = "VPC ID where the security group will be created"
  type        = string
}

variable "allowed_cidrs" {
  description = "List of CIDR blocks allowed to access Grafana"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

output "security_group_id" {
  description = "Security Group ID for TIG Stack"
  value       = aws_security_group.tig_stack.id
}
```

## Validation and Testing

### Test Security Group Configuration
```bash
# Test Grafana accessibility
curl -I http://your-instance-ip:3000

# Test from different networks
# Should succeed from allowed IPs
curl -I --connect-timeout 5 http://your-instance-ip:3000

# Should fail from blocked IPs
# (Test from different location or remove your IP temporarily)
```

### Security Group Audit Script
```bash
#!/bin/bash
# audit-security-groups.sh

INSTANCE_ID="i-1234567890abcdef0"
SG_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

echo "Auditing Security Group: $SG_ID"
echo "==================================="

# Check inbound rules
echo "Inbound Rules:"
aws ec2 describe-security-groups --group-ids $SG_ID --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' --output table

# Check outbound rules
echo "Outbound Rules:"
aws ec2 describe-security-groups --group-ids $SG_ID --query 'SecurityGroups[0].IpPermissionsEgress[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' --output table

# Check for overly permissive rules
echo "Security Warnings:"
aws ec2 describe-security-groups --group-ids $SG_ID --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' --output table
```

## Common Issues and Solutions

### Issue: Cannot Access Grafana
**Cause**: Security group not allowing port 3000
**Solution**: Add inbound rule for TCP port 3000 from your IP

### Issue: Installation Fails
**Cause**: Outbound rules blocking package downloads
**Solution**: Ensure HTTPS (443) and HTTP (80) outbound access

### Issue: Containers Can't Communicate
**Cause**: Internal Docker networking issue (not security group related)
**Solution**: Check Docker network configuration, not security groups

### Issue: Intermittent Access
**Cause**: Dynamic IP address changes
**Solution**: Use CIDR range instead of specific IP, or update rules regularly

## Monitoring Security Group Changes

### CloudWatch Events Rule
```json
{
  "Rules": [
    {
      "Name": "SecurityGroupChanges",
      "EventPattern": {
        "source": ["aws.ec2"],
        "detail-type": ["AWS API Call via CloudTrail"],
        "detail": {
          "eventSource": ["ec2.amazonaws.com"],
          "eventName": [
            "AuthorizeSecurityGroupIngress",
            "AuthorizeSecurityGroupEgress",
            "RevokeSecurityGroupIngress",
            "RevokeSecurityGroupEgress"
          ]
        }
      },
      "State": "ENABLED",
      "Targets": [
        {
          "Id": "1",
          "Arn": "arn:aws:sns:region:account:security-alerts"
        }
      ]
    }
  ]
}
```

This comprehensive security group configuration ensures your TIG Stack deployment is both functional and secure.