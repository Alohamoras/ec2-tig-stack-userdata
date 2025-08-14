# Design Document

## Overview

The EC2 User Data TIG Stack solution creates a self-contained user data script that installs Docker and deploys the TIG stack by embedding the essential configuration files directly in the script. This eliminates external dependencies and ensures reliable deployment.

This approach keeps the script manageable (~80-100 lines), completely self-contained, and leverages the existing proven configuration with EC2-specific optimizations.

## Architecture

### High-Level Flow
1. **Bootstrap Phase**: Install Docker and Docker Compose (10-15 lines)
2. **File Creation Phase**: Create directory structure and embed configuration files (30-40 lines)
3. **Configuration Phase**: Generate secure passwords and create .env file (10-15 lines)
4. **Deployment Phase**: Start the stack with docker-compose up (5 lines)

### Component Interaction
```
EC2 Instance Launch
    ↓
User Data Script (~80-100 lines)
    ↓
Docker Install → File Creation → Password Generation → Stack Deployment
```

## Components and Interfaces

### 1. User Data Script (`user-data.sh`)
**Purpose**: Self-contained script that installs Docker and deploys the TIG stack

**Key Functions**:
- Install Docker and Docker Compose (using official installation methods)
- Create directory structure for the TIG stack
- Generate all configuration files using embedded heredoc blocks
- Generate secure random passwords
- Create the .env file with EC2-appropriate settings
- Start the stack with docker-compose up -d

**Interface**: Executed by cloud-init during EC2 instance initialization

### 2. Embedded Configuration Strategy
**Purpose**: Include all essential files directly in the script for complete self-containment

**Embedded Files**:
- `docker-compose.yml`: The existing container orchestration configuration
- `.env`: Environment variables with generated secure passwords
- `grafana/Dockerfile`: Grafana container build configuration
- `influxdb/Dockerfile`: InfluxDB container build configuration  
- `telegraf/Dockerfile`: Telegraf container build configuration
- Essential configuration files for each service

**Benefits**: No network dependencies, guaranteed availability, version consistency

### 3. Environment Variable System
**Purpose**: Allow customization of the monitoring stack without script modification

**Default Variables**:
```bash
TIG_GRAFANA_PORT=${TIG_GRAFANA_PORT:-3000}
TIG_GRAFANA_USER=${TIG_GRAFANA_USER:-admin}
TIG_GRAFANA_PASSWORD=${TIG_GRAFANA_PASSWORD:-$(openssl rand -base64 12)}
TIG_INFLUXDB_PORT=${TIG_INFLUXDB_PORT:-8086}
TIG_INFLUXDB_PASSWORD=${TIG_INFLUXDB_PASSWORD:-$(openssl rand -base64 12)}
```

**Interface**: EC2 user data environment variables or instance metadata

### 4. Logging System
**Purpose**: Comprehensive logging for troubleshooting and monitoring script execution

**Log Locations**:
- `/var/log/tig-stack-install.log`: Main installation log
- `/var/log/cloud-init-output.log`: Standard cloud-init logging
- Container logs via Docker logging driver

**Interface**: Standard Linux logging mechanisms and Docker logs

## Data Models

### Configuration Structure
```
/home/ec2-user/tig-stack/    # Created by user data script
├── docker-compose.yml       # Generated from embedded template
├── .env                     # Generated with secure passwords
├── grafana/
│   ├── Dockerfile          # Generated from embedded template
│   └── config/             # Generated configuration files
├── influxdb/
│   ├── Dockerfile          # Generated from embedded template
│   └── config/             # Generated configuration files
└── telegraf/
    ├── Dockerfile          # Generated from embedded template
    └── config/             # Generated configuration files
```

### Environment Variables Model
```bash
# Core Configuration
CONTAINER_PREFIX=tig
TIG_INSTALL_DIR=/opt/tig-stack

# Service Ports
GRAFANA_PORT=3000
INFLUXDB_PORT=8086

# Authentication
GRAFANA_USER=admin
GRAFANA_PASSWORD=<generated>
INFLUXDB_ADMIN_USER=grafana
INFLUXDB_ADMIN_PASSWORD=<generated>

# Service Configuration
TELEGRAF_HOST=telegraf
INFLUXDB_HOST=influxdb
INFLUXDB_DATABASE=metrics
```

## Error Handling

### Installation Failures
- **Docker Installation**: Retry with alternative installation methods (apt vs snap)
- **Permission Issues**: Automatic user group management and permission fixes
- **Network Issues**: Retry mechanisms for package downloads
- **Disk Space**: Pre-flight checks for available space

### Runtime Failures
- **Container Startup**: Health checks and automatic restart policies
- **Service Dependencies**: Proper container linking and startup ordering
- **Configuration Errors**: Validation of generated configuration files

### Logging Strategy
- All operations logged with timestamps
- Error conditions logged with context and suggested remediation
- Success milestones clearly marked
- Integration with CloudWatch Logs for centralized monitoring

## Testing Strategy

### Simple Validation Approach
- **Script Testing**: Test the user data script on a fresh EC2 instance
- **Service Verification**: Check that Grafana is accessible on port 3000
- **Container Health**: Verify all three containers are running
- **Basic Functionality**: Confirm dashboards show system metrics

### Performance Targets
- **Installation Time**: Complete setup in under 3 minutes
- **Script Size**: Keep user data script under 100 lines
- **Dependencies**: Minimal external dependencies (Docker only)

## Security Considerations

### Authentication
- Generate random passwords for all admin accounts
- Store credentials securely in environment variables
- Use non-default usernames where possible

### Network Security
- Bind services only to necessary interfaces
- Use Docker networks for inter-container communication
- Document required security group rules

### File Permissions
- Create dedicated user for TIG stack operations
- Set appropriate file permissions on configuration files
- Use Docker user namespacing where applicable

### Updates and Maintenance
- Pin Docker image versions for consistency
- Document update procedures for security patches
- Implement backup strategies for persistent data