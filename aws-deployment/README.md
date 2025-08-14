# TIG Stack c5.4xlarge Testing Deployment

This directory contains scripts and templates for testing the TIG Stack on a c5.4xlarge EC2 instance.

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **EC2 Key Pair** created in your target region
3. **Default VPC** available (or specify a custom VPC)

## Quick Start

### 1. Run Setup Script (Recommended)

```bash
cd aws-deployment
./setup.sh
```

This will:
- Verify your AWS CLI configuration
- Configure your EC2 key pair name
- Set your preferred AWS region
- Guide you through key file placement options

### 2. Manual Configuration (Alternative)

If you prefer manual setup, edit these variables:

In `launch-instance.sh`:
```bash
KEY_NAME="your-key-pair-name"  # Replace with your key pair name
REGION="us-east-1"             # Change to your preferred region
```

In `monitor-deployment.sh`:
```bash
KEY_NAME="your-key-pair-name"  # Replace with your key pair name
```

### 3. Launch the Instance

```bash
chmod +x *.sh
./launch-instance.sh
```

This will:
- Create a security group with proper rules
- Launch a c5.4xlarge instance with optimized user data
- Display access information

### 4. Monitor the Deployment

```bash
./monitor-deployment.sh
```

Choose from:
1. One-time status check
2. Continuous monitoring (recommended)
3. Show access information only
4. Check installation logs

### 5. Access Your TIG Stack

Once deployment is complete (3-5 minutes):
- **Grafana**: http://YOUR-INSTANCE-IP:3000
- **Username**: admin
- **Password**: Check `/opt/tig-stack/.env` on the instance

### 6. Clean Up Resources

```bash
./cleanup.sh
```

This will terminate the instance and delete all created AWS resources.

## Files Description

| File | Purpose |
|------|---------|
| `setup.sh` | Interactive setup script (recommended) |
| `security-group.yaml` | CloudFormation template for security group |
| `user-data-c5-4xlarge.sh` | Optimized user data script for large instance |
| `launch-instance.sh` | Main script to launch and configure instance |
| `monitor-deployment.sh` | Monitor deployment progress and status |
| `cleanup.sh` | Clean up all created AWS resources |

## Key File Placement Options

You have three options for your EC2 key pair file:

### Option 1: aws-deployment directory (Recommended)
```bash
# Copy your key file to the deployment directory
cp ~/Downloads/your-key.pem ./aws-deployment/
chmod 400 ./aws-deployment/your-key.pem
```

### Option 2: ~/.ssh directory
```bash
# Place in your SSH directory
cp ~/Downloads/your-key.pem ~/.ssh/
chmod 400 ~/.ssh/your-key.pem
```

### Option 3: Any location with absolute path
```bash
# Keep anywhere and update scripts with full path
# The setup script will handle this for you
```

**Security Note**: Key files are automatically excluded from git commits via `.gitignore`.

## Instance Specifications

- **Instance Type**: c5.4xlarge
- **vCPUs**: 16
- **Memory**: 32 GB RAM
- **Network**: Up to 10 Gbps
- **Storage**: EBS-optimized

## Security Group Rules

### Inbound
- SSH (22): Your IP only
- Grafana (3000): Your IP only  
- InfluxDB (8086): Your IP only (testing)

### Outbound
- HTTPS (443): All destinations (package downloads)
- HTTP (80): All destinations (package downloads)
- DNS (53): All destinations (name resolution)

## Monitoring Features

The deployment includes:
- Real-time installation logging
- Container status monitoring
- Resource usage tracking
- Automatic validation checks
- Performance metrics collection

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Check your key pair name and file permissions
   - Verify security group allows SSH from your IP

2. **Instance Launch Failed**
   - Check AWS CLI configuration and permissions
   - Verify the specified region and availability zones

3. **TIG Stack Not Accessible**
   - Wait 3-5 minutes for full deployment
   - Check installation logs with monitor script
   - Verify security group rules

### Debug Commands

```bash
# Check installation progress
ssh -i your-key.pem ec2-user@INSTANCE-IP 'tail -f /var/log/tig-stack-install.log'

# Check container status
ssh -i your-key.pem ec2-user@INSTANCE-IP 'docker ps'

# Check system resources
ssh -i your-key.pem ec2-user@INSTANCE-IP 'htop'

# Check deployment markers
ssh -i your-key.pem ec2-user@INSTANCE-IP 'cat /tmp/tig-deployment-*.txt'
```

## Performance Testing

The c5.4xlarge instance provides excellent performance for the TIG stack:
- Fast Docker image builds and container startup
- High-performance metrics collection
- Responsive Grafana dashboards
- Efficient InfluxDB operations

Expected deployment time: **2-3 minutes** (vs 5-8 minutes on smaller instances)

## Cost Considerations

- **c5.4xlarge**: ~$0.68/hour (us-east-1)
- **EBS Storage**: ~$0.10/GB/month
- **Data Transfer**: First 1GB/month free

Remember to run `cleanup.sh` when testing is complete to avoid ongoing charges.

## Next Steps

After successful deployment:
1. Explore the pre-configured Grafana dashboards
2. Test custom metrics collection
3. Evaluate performance under load
4. Consider production deployment optimizations