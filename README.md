# EC2 User Data TIG Stack

Automatically deploy a complete monitoring stack (Telegraf/InfluxDB/Grafana) on EC2 instances using user data scripts.

## Overview

This project provides a self-contained user data script that automatically installs Docker and deploys the TIG monitoring stack when an EC2 instance launches. The script embeds all necessary configuration files, eliminating external dependencies and ensuring reliable deployment.

## Features

- **Automatic Installation**: Complete setup in under 5 minutes
- **Multi-OS Support**: Works with Amazon Linux 2, Ubuntu, and CentOS/RHEL
- **Self-Contained**: No external file dependencies beyond Docker images
- **Secure by Default**: Generates random passwords and follows security best practices
- **Comprehensive Logging**: Detailed logs for troubleshooting and monitoring
- **Customizable**: Environment variable support for different configurations

## Quick Start

1. Copy the `user-data.sh` script content
2. Configure your EC2 security groups (see [Security Group Requirements](#security-group-requirements))
3. Launch an EC2 instance with the script as user data
4. Wait 3-5 minutes for installation to complete
5. Access Grafana at `http://your-instance-ip:3000`

## Default Configuration

- **Grafana**: Port 3000, admin user with generated password
- **InfluxDB**: Port 8086, internal communication only
- **Telegraf**: Collects system and Docker metrics
- **Installation Directory**: `/opt/tig-stack`
- **Log File**: `/var/log/tig-stack-install.log`

## Security Group Requirements

Your EC2 instance must have the following security group rules. For detailed configuration including CloudFormation templates and advanced setups, see [SECURITY-GROUPS.md](SECURITY-GROUPS.md).

### Minimum Required Rules

#### Inbound Rules
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | Your IP/CIDR | Grafana web interface |

#### Outbound Rules
| Type | Protocol | Port Range | Destination | Description |
|------|----------|------------|-------------|-------------|
| HTTPS | TCP | 443 | 0.0.0.0/0 | Package downloads |
| HTTP | TCP | 80 | 0.0.0.0/0 | Package downloads |

## Environment Variable Customization

Customize the installation by setting environment variables in your user data script. See [ENVIRONMENT-VARIABLES.md](ENVIRONMENT-VARIABLES.md) for complete configuration options.

```bash
#!/bin/bash

# Custom configuration
export TIG_GRAFANA_PORT=3001
export TIG_GRAFANA_USER=admin
export TIG_GRAFANA_PASSWORD=your-secure-password
export TIG_INFLUXDB_PORT=8087
export CONTAINER_PREFIX=monitoring

# Run the installation script
curl -sSL https://your-script-location/user-data.sh | bash
```

### Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TIG_GRAFANA_PORT` | 3000 | Grafana web interface port |
| `TIG_GRAFANA_USER` | admin | Grafana admin username |
| `TIG_GRAFANA_PASSWORD` | Generated | Grafana admin password |
| `TIG_INFLUXDB_PORT` | 8086 | InfluxDB port |
| `CONTAINER_PREFIX` | tig | Docker container name prefix |

For a complete list of all available variables and configuration examples, see [ENVIRONMENT-VARIABLES.md](ENVIRONMENT-VARIABLES.md).

## Monitoring Capabilities

Once deployed, the TIG stack provides:

### System Monitoring
- CPU usage and load averages
- Memory utilization
- Disk space and I/O metrics
- Network interface statistics
- System uptime and processes

### Docker Monitoring
- Container status and health
- Resource usage per container
- Docker daemon metrics
- Image and volume statistics

### Pre-configured Dashboards
- **System Monitoring**: Comprehensive system metrics
- **Docker Monitoring**: Container and Docker daemon metrics

## Accessing Your Monitoring Stack

1. **Find your instance IP**: Check the EC2 console or use `curl http://169.254.169.254/latest/meta-data/public-ipv4`
2. **Open Grafana**: Navigate to `http://your-instance-ip:3000`
3. **Login**: Use `admin` as username and check the password in `/opt/tig-stack/.env`
4. **View Dashboards**: Pre-configured dashboards are available immediately

## Documentation

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Comprehensive troubleshooting guide
- **[SECURITY-GROUPS.md](SECURITY-GROUPS.md)** - Detailed security group configuration
- **[ENVIRONMENT-VARIABLES.md](ENVIRONMENT-VARIABLES.md)** - Complete environment variable reference

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed troubleshooting information.

## Architecture

The TIG stack consists of three main components:

- **Telegraf**: Metrics collection agent
- **InfluxDB**: Time-series database for metrics storage
- **Grafana**: Visualization and dashboarding platform

All components run in Docker containers with persistent data storage and automatic restart policies.

## Support

For issues and questions:
1. Check the installation logs at `/var/log/tig-stack-install.log`
2. Review the troubleshooting guide
3. Examine container logs with `docker logs <container-name>`

## License

This project is licensed under the MIT License - see the LICENSE file for details.