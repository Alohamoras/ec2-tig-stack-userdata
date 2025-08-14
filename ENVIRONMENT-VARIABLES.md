# Environment Variables Configuration Guide

This document provides comprehensive information about customizing the TIG Stack deployment using environment variables.

## Overview

The TIG Stack user data script supports extensive customization through environment variables. This allows you to adapt the monitoring stack for different environments, security requirements, and use cases without modifying the core script.

## Setting Environment Variables

### Method 1: In User Data Script (Recommended)

```bash
#!/bin/bash

# Set custom environment variables
export TIG_GRAFANA_PORT=3001
export TIG_GRAFANA_USER=monitoring-admin
export TIG_GRAFANA_PASSWORD=MySecurePassword123!
export CONTAINER_PREFIX=prod-monitoring

# Download and execute the TIG stack script
curl -sSL https://your-script-location/user-data.sh | bash
```

### Method 2: EC2 Instance Metadata

```bash
# Set via AWS CLI when launching instance
aws ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t3.medium \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=TIG_GRAFANA_PORT,Value=3001}]'
```

### Method 3: Systems Manager Parameter Store

```bash
#!/bin/bash

# Retrieve from Parameter Store in user data
export TIG_GRAFANA_PASSWORD=$(aws ssm get-parameter --name "/tig-stack/grafana/password" --with-decryption --query 'Parameter.Value' --output text)
export TIG_INFLUXDB_PASSWORD=$(aws ssm get-parameter --name "/tig-stack/influxdb/password" --with-decryption --query 'Parameter.Value' --output text)

# Execute installation script
curl -sSL https://your-script-location/user-data.sh | bash
```

## Complete Variable Reference

### Core Configuration Variables

#### `TIG_INSTALL_DIR`
- **Default**: `/opt/tig-stack`
- **Description**: Base directory for TIG stack installation
- **Example**: `export TIG_INSTALL_DIR=/home/ec2-user/monitoring`
- **Impact**: Changes where all configuration files and data are stored

#### `LOG_FILE`
- **Default**: `/var/log/tig-stack-install.log`
- **Description**: Location of installation log file
- **Example**: `export LOG_FILE=/tmp/tig-install.log`
- **Impact**: Changes where installation logs are written

#### `TIG_USER`
- **Default**: `ec2-user`
- **Description**: System user for running TIG stack services
- **Example**: `export TIG_USER=ubuntu`
- **Impact**: Changes file ownership and Docker group membership

### Grafana Configuration

#### `TIG_GRAFANA_PORT`
- **Default**: `3000`
- **Description**: Port for Grafana web interface
- **Example**: `export TIG_GRAFANA_PORT=8080`
- **Security**: Ensure security groups allow the chosen port
- **Impact**: Changes external access port for dashboards

#### `TIG_GRAFANA_USER`
- **Default**: `admin`
- **Description**: Grafana administrator username
- **Example**: `export TIG_GRAFANA_USER=grafana-admin`
- **Security**: Use non-default usernames for better security
- **Impact**: Changes login credentials for Grafana

#### `TIG_GRAFANA_PASSWORD`
- **Default**: Auto-generated secure password
- **Description**: Grafana administrator password
- **Example**: `export TIG_GRAFANA_PASSWORD=MySecurePassword123!`
- **Security**: Use strong passwords (12+ characters, mixed case, numbers, symbols)
- **Impact**: Sets login password for Grafana admin user

#### `GRAFANA_PLUGINS_ENABLED`
- **Default**: `true`
- **Description**: Whether to install Grafana plugins automatically
- **Example**: `export GRAFANA_PLUGINS_ENABLED=false`
- **Impact**: Disables automatic plugin installation for faster startup

#### `GRAFANA_PLUGINS`
- **Default**: All available plugins
- **Description**: Specific plugins to install (space-separated)
- **Example**: `export GRAFANA_PLUGINS="grafana-clock-panel grafana-piechart-panel"`
- **Impact**: Installs only specified plugins instead of all available

### InfluxDB Configuration

#### `TIG_INFLUXDB_PORT`
- **Default**: `8086`
- **Description**: InfluxDB API port
- **Example**: `export TIG_INFLUXDB_PORT=8087`
- **Security**: Generally should not be exposed externally
- **Impact**: Changes internal communication port

#### `TIG_INFLUXDB_PASSWORD`
- **Default**: Auto-generated secure password
- **Description**: InfluxDB admin password
- **Example**: `export TIG_INFLUXDB_PASSWORD=InfluxSecurePass456!`
- **Security**: Use strong passwords for database access
- **Impact**: Sets database admin password

#### `INFLUXDB_ADMIN_USER`
- **Default**: `grafana`
- **Description**: InfluxDB admin username
- **Example**: `export INFLUXDB_ADMIN_USER=dbadmin`
- **Impact**: Changes database admin username

#### `INFLUXDB_DATABASE`
- **Default**: `telegraf`
- **Description**: Default database name for metrics
- **Example**: `export INFLUXDB_DATABASE=metrics`
- **Impact**: Changes where Telegraf stores collected metrics

#### `INFLUXDB_HOST`
- **Default**: `influxdb`
- **Description**: InfluxDB hostname for container communication
- **Example**: `export INFLUXDB_HOST=influxdb-server`
- **Impact**: Changes internal container networking

### Telegraf Configuration

#### `TELEGRAF_HOST`
- **Default**: `telegraf`
- **Description**: Telegraf hostname for container identification
- **Example**: `export TELEGRAF_HOST=metrics-collector`
- **Impact**: Changes container hostname in metrics

#### `TELEGRAF_INTERVAL`
- **Default**: `10s`
- **Description**: Metrics collection interval
- **Example**: `export TELEGRAF_INTERVAL=30s`
- **Impact**: Changes how frequently metrics are collected

#### `TELEGRAF_HOSTNAME`
- **Default**: Instance hostname
- **Description**: Hostname tag for collected metrics
- **Example**: `export TELEGRAF_HOSTNAME=prod-web-01`
- **Impact**: Changes hostname tag in all metrics

### Container Configuration

#### `CONTAINER_PREFIX`
- **Default**: `tig`
- **Description**: Prefix for Docker container names
- **Example**: `export CONTAINER_PREFIX=monitoring`
- **Impact**: Changes container names to `monitoring_grafana`, `monitoring_influxdb`, etc.

#### `DOCKER_NETWORK_NAME`
- **Default**: `tig-stack_default`
- **Description**: Docker network name for container communication
- **Example**: `export DOCKER_NETWORK_NAME=monitoring-network`
- **Impact**: Changes internal Docker network configuration

## Configuration Examples

### Development Environment
```bash
#!/bin/bash

# Development configuration - relaxed security, verbose logging
export TIG_GRAFANA_PORT=3000
export TIG_GRAFANA_USER=dev-admin
export TIG_GRAFANA_PASSWORD=DevPassword123
export TIG_INFLUXDB_PORT=8086
export CONTAINER_PREFIX=dev
export TELEGRAF_INTERVAL=5s
export LOG_FILE=/tmp/tig-dev-install.log

# Execute installation
curl -sSL https://your-script-location/user-data.sh | bash
```

### Production Environment
```bash
#!/bin/bash

# Production configuration - enhanced security
export TIG_GRAFANA_PORT=3000
export TIG_GRAFANA_USER=prod-monitoring
export TIG_GRAFANA_PASSWORD=$(aws ssm get-parameter --name "/prod/tig/grafana/password" --with-decryption --query 'Parameter.Value' --output text)
export TIG_INFLUXDB_PASSWORD=$(aws ssm get-parameter --name "/prod/tig/influxdb/password" --with-decryption --query 'Parameter.Value' --output text)
export CONTAINER_PREFIX=prod-monitoring
export TELEGRAF_INTERVAL=30s
export TELEGRAF_HOSTNAME=prod-web-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Execute installation
curl -sSL https://your-script-location/user-data.sh | bash
```

### High-Performance Environment
```bash
#!/bin/bash

# High-performance configuration - optimized for large-scale monitoring
export TIG_GRAFANA_PORT=3000
export TIG_INFLUXDB_PORT=8086
export TELEGRAF_INTERVAL=60s
export CONTAINER_PREFIX=hpc-monitoring
export GRAFANA_PLUGINS_ENABLED=false  # Skip plugins for faster startup
export INFLUXDB_DATABASE=hpc-metrics

# Custom retention policy for high-volume metrics
export INFLUXDB_RETENTION_POLICY=7d

# Execute installation
curl -sSL https://your-script-location/user-data.sh | bash
```

### Multi-Environment Setup
```bash
#!/bin/bash

# Determine environment from instance tags
ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)" "Name=key,Values=Environment" --query 'Tags[0].Value' --output text)

case $ENVIRONMENT in
  "production")
    export TIG_GRAFANA_PORT=3000
    export CONTAINER_PREFIX=prod
    export TELEGRAF_INTERVAL=30s
    ;;
  "staging")
    export TIG_GRAFANA_PORT=3001
    export CONTAINER_PREFIX=staging
    export TELEGRAF_INTERVAL=15s
    ;;
  "development")
    export TIG_GRAFANA_PORT=3002
    export CONTAINER_PREFIX=dev
    export TELEGRAF_INTERVAL=5s
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

# Execute installation
curl -sSL https://your-script-location/user-data.sh | bash
```

## Security Best Practices

### Password Management
```bash
# Generate secure passwords
export TIG_GRAFANA_PASSWORD=$(openssl rand -base64 32)
export TIG_INFLUXDB_PASSWORD=$(openssl rand -base64 32)

# Store in AWS Systems Manager Parameter Store
aws ssm put-parameter --name "/tig-stack/grafana/password" --value "$TIG_GRAFANA_PASSWORD" --type "SecureString"
aws ssm put-parameter --name "/tig-stack/influxdb/password" --value "$TIG_INFLUXDB_PASSWORD" --type "SecureString"
```

### Environment-Specific Configurations
```bash
# Use different ports per environment to avoid conflicts
case $ENVIRONMENT in
  "prod") export TIG_GRAFANA_PORT=3000 ;;
  "staging") export TIG_GRAFANA_PORT=3001 ;;
  "dev") export TIG_GRAFANA_PORT=3002 ;;
esac
```

### Secrets Management with AWS Secrets Manager
```bash
#!/bin/bash

# Retrieve secrets from AWS Secrets Manager
SECRET=$(aws secretsmanager get-secret-value --secret-id "tig-stack/credentials" --query 'SecretString' --output text)
export TIG_GRAFANA_PASSWORD=$(echo $SECRET | jq -r '.grafana_password')
export TIG_INFLUXDB_PASSWORD=$(echo $SECRET | jq -r '.influxdb_password')

# Execute installation
curl -sSL https://your-script-location/user-data.sh | bash
```

## Validation and Testing

### Environment Variable Validation Script
```bash
#!/bin/bash

# validate-env-vars.sh
echo "=== TIG Stack Environment Variables ==="

# Check required variables
required_vars=("TIG_GRAFANA_PORT" "TIG_INFLUXDB_PORT")
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "WARNING: $var is not set, using default"
  else
    echo "$var=${!var}"
  fi
done

# Validate port numbers
if ! [[ "$TIG_GRAFANA_PORT" =~ ^[0-9]+$ ]] || [ "$TIG_GRAFANA_PORT" -lt 1024 ] || [ "$TIG_GRAFANA_PORT" -gt 65535 ]; then
  echo "ERROR: TIG_GRAFANA_PORT must be a valid port number (1024-65535)"
  exit 1
fi

# Validate password strength
if [ ${#TIG_GRAFANA_PASSWORD} -lt 8 ]; then
  echo "WARNING: TIG_GRAFANA_PASSWORD should be at least 8 characters"
fi

echo "Environment validation completed"
```

### Testing Different Configurations
```bash
# Test with custom ports
export TIG_GRAFANA_PORT=8080
export TIG_INFLUXDB_PORT=8087

# Verify ports are available
if netstat -tuln | grep -q ":$TIG_GRAFANA_PORT "; then
  echo "ERROR: Port $TIG_GRAFANA_PORT is already in use"
  exit 1
fi

# Test configuration
curl -sSL https://your-script-location/user-data.sh | bash
```

## Troubleshooting Environment Variables

### Common Issues

#### Variable Not Taking Effect
```bash
# Check if variable is set
echo $TIG_GRAFANA_PORT

# Check in container environment
docker exec tig_grafana env | grep GRAFANA

# Verify in configuration files
cat /opt/tig-stack/.env
```

#### Port Conflicts
```bash
# Check what's using the port
sudo netstat -tlnp | grep :3000

# Find alternative ports
for port in {3001..3010}; do
  if ! netstat -tuln | grep -q ":$port "; then
    echo "Port $port is available"
    break
  fi
done
```

#### Permission Issues
```bash
# Check if user exists
id $TIG_USER

# Verify Docker group membership
groups $TIG_USER | grep docker
```

### Debug Mode
```bash
# Enable debug logging
export DEBUG=true
export LOG_LEVEL=DEBUG

# Execute with verbose output
bash -x user-data.sh
```

This comprehensive guide covers all aspects of environment variable configuration for the TIG Stack deployment, enabling flexible and secure customization for any environment.