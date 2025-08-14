# TIG Stack Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the EC2 User Data TIG Stack installation.

## Quick Diagnostics

### Check Installation Status
```bash
# View installation logs
sudo tail -f /var/log/tig-stack-install.log

# Check if containers are running
docker ps

# Check container health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Verify Services
```bash
# Test Grafana accessibility
curl -I http://localhost:3000

# Check InfluxDB
curl -I http://localhost:8086/ping

# View container logs
docker logs tig_grafana
docker logs tig_influxdb
docker logs tig_telegraf
```

## Common Issues and Solutions

### 1. Installation Script Fails

**Symptoms:**
- Script exits with error codes
- Installation log shows failures
- Services don't start

**Diagnosis:**
```bash
# Check the installation log
sudo cat /var/log/tig-stack-install.log

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Check system logs
sudo journalctl -u cloud-init-output
```

**Common Causes and Solutions:**

#### Insufficient Disk Space
```bash
# Check available space
df -h

# Solution: Use larger instance or clean up space
sudo apt-get clean  # Ubuntu/Debian
sudo yum clean all  # Amazon Linux/CentOS
```

#### Network Connectivity Issues
```bash
# Test internet connectivity
ping -c 3 google.com

# Test Docker Hub connectivity
curl -I https://registry-1.docker.io/

# Solution: Check security groups and NACLs
```

#### Permission Issues
```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# Fix Docker permissions
sudo chmod 666 /var/run/docker.sock
sudo usermod -aG docker ec2-user
```

### 2. Docker Installation Fails

**Symptoms:**
- Docker commands not found
- Docker service not running
- Permission denied errors

**Diagnosis:**
```bash
# Check if Docker is installed
which docker
docker --version

# Check Docker service status
sudo systemctl status docker

# Check Docker daemon logs
sudo journalctl -u docker
```

**Solutions:**

#### Manual Docker Installation (Amazon Linux 2)
```bash
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
```

#### Manual Docker Installation (Ubuntu)
```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ubuntu
```

#### Fix Docker Compose Installation
```bash
# Download Docker Compose manually
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 3. Containers Won't Start

**Symptoms:**
- `docker ps` shows no running containers
- Containers exit immediately
- Port binding errors

**Diagnosis:**
```bash
# Check all containers (including stopped)
docker ps -a

# Check container logs
docker logs tig_grafana
docker logs tig_influxdb
docker logs tig_telegraf

# Check Docker Compose status
cd /opt/tig-stack
docker-compose ps
```

**Solutions:**

#### Port Conflicts
```bash
# Check what's using the ports
sudo netstat -tlnp | grep :3000
sudo netstat -tlnp | grep :8086

# Solution: Change ports in .env file
cd /opt/tig-stack
sudo nano .env
# Modify TIG_GRAFANA_PORT and TIG_INFLUXDB_PORT
docker-compose down && docker-compose up -d
```

#### Memory Issues
```bash
# Check available memory
free -h

# Check container resource usage
docker stats

# Solution: Use larger instance type or optimize containers
```

#### Configuration File Issues
```bash
# Validate docker-compose.yml
cd /opt/tig-stack
docker-compose config

# Recreate containers with fresh config
docker-compose down
docker-compose up -d --force-recreate
```

### 4. Grafana Not Accessible

**Symptoms:**
- Cannot connect to Grafana web interface
- Connection timeout or refused
- Blank page or errors

**Diagnosis:**
```bash
# Check if Grafana container is running
docker ps | grep grafana

# Check Grafana logs
docker logs tig_grafana

# Test local connectivity
curl -I http://localhost:3000

# Check if port is open
sudo netstat -tlnp | grep :3000
```

**Solutions:**

#### Security Group Issues
1. Go to EC2 Console → Security Groups
2. Find your instance's security group
3. Add inbound rule: Type=HTTP, Port=3000, Source=Your IP
4. Save changes

#### Grafana Container Issues
```bash
# Restart Grafana container
docker restart tig_grafana

# Check Grafana configuration
docker exec tig_grafana cat /etc/grafana/grafana.ini

# Reset Grafana admin password
docker exec -it tig_grafana grafana-cli admin reset-admin-password newpassword
```

#### Firewall Issues (if applicable)
```bash
# Check if firewall is blocking (Ubuntu)
sudo ufw status

# Allow port 3000
sudo ufw allow 3000

# Check iptables rules
sudo iptables -L
```

### 5. No Data in Dashboards

**Symptoms:**
- Grafana loads but dashboards show no data
- "No data points" messages
- Telegraf not collecting metrics

**Diagnosis:**
```bash
# Check Telegraf logs
docker logs tig_telegraf

# Check InfluxDB logs
docker logs tig_influxdb

# Test InfluxDB connectivity
curl -I http://localhost:8086/ping

# Check if data is being written to InfluxDB
docker exec -it tig_influxdb influx -execute "SHOW DATABASES"
```

**Solutions:**

#### Telegraf Configuration Issues
```bash
# Check Telegraf configuration
docker exec tig_telegraf cat /etc/telegraf/telegraf.conf

# Restart Telegraf
docker restart tig_telegraf

# Check system permissions for Telegraf
ls -la /var/run/docker.sock
```

#### InfluxDB Connection Issues
```bash
# Check InfluxDB is accessible
docker exec -it tig_influxdb influx -execute "SHOW DATABASES"

# Verify database exists
docker exec -it tig_influxdb influx -execute "USE telegraf; SHOW MEASUREMENTS"

# Check Grafana data source configuration in web UI
```

### 6. Performance Issues

**Symptoms:**
- Slow dashboard loading
- High CPU/memory usage
- Container restarts

**Diagnosis:**
```bash
# Check system resources
top
htop
free -h
df -h

# Check container resource usage
docker stats

# Check container restart counts
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RestartCount}}"
```

**Solutions:**

#### Optimize Container Resources
```bash
# Edit docker-compose.yml to add resource limits
cd /opt/tig-stack
sudo nano docker-compose.yml

# Add to each service:
# deploy:
#   resources:
#     limits:
#       memory: 512M
#     reservations:
#       memory: 256M
```

#### Reduce Data Retention
```bash
# Configure InfluxDB retention policy
docker exec -it tig_influxdb influx -execute "
CREATE RETENTION POLICY \"30_days\" ON \"telegraf\" DURATION 30d REPLICATION 1 DEFAULT
"
```

## Log Locations

### Installation Logs
- `/var/log/tig-stack-install.log` - Main installation log
- `/var/log/cloud-init-output.log` - Cloud-init output
- `/var/log/tig-stack-latest.log` - Symlink to latest log

### Container Logs
```bash
# View container logs
docker logs tig_grafana
docker logs tig_influxdb
docker logs tig_telegraf

# Follow logs in real-time
docker logs -f tig_grafana
```

### System Logs
```bash
# Docker service logs
sudo journalctl -u docker

# System messages
sudo tail -f /var/log/messages  # CentOS/RHEL
sudo tail -f /var/log/syslog    # Ubuntu
```

## Recovery Procedures

### Complete Reinstallation
```bash
# Stop and remove all containers
docker-compose down
docker system prune -a

# Remove installation directory
sudo rm -rf /opt/tig-stack

# Re-run the user data script
sudo bash /var/lib/cloud/instance/user-data.txt
```

### Reset Grafana
```bash
# Stop Grafana
docker stop tig_grafana

# Remove Grafana data volume
docker volume rm tig-stack_grafana-storage

# Restart stack
docker-compose up -d
```

### Reset InfluxDB
```bash
# Stop all containers
docker-compose down

# Remove InfluxDB data
sudo rm -rf /var/lib/influxdb/*

# Restart stack
docker-compose up -d
```

## Getting Help

### Collect Diagnostic Information
```bash
# Create diagnostic report
cat > diagnostic-report.txt << EOF
=== System Information ===
$(uname -a)
$(cat /etc/os-release)

=== Docker Information ===
$(docker --version)
$(docker-compose --version)
$(docker ps -a)

=== Container Logs ===
$(docker logs tig_grafana 2>&1 | tail -50)
$(docker logs tig_influxdb 2>&1 | tail -50)
$(docker logs tig_telegraf 2>&1 | tail -50)

=== Installation Log ===
$(tail -100 /var/log/tig-stack-install.log)

=== System Resources ===
$(free -h)
$(df -h)
EOF
```

### Contact Information
- Check the main README.md for support channels
- Include the diagnostic report when seeking help
- Provide your EC2 instance type and region information