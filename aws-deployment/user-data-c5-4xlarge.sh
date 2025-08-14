#!/bin/bash

# Optimized TIG Stack User Data for c5.4xlarge Testing
# Instance: c5.4xlarge (16 vCPUs, 32 GB RAM)
# Purpose: Performance testing and validation

# Custom environment variables for large instance testing
export TIG_GRAFANA_PORT=3000
export TIG_GRAFANA_USER=admin
export TIG_GRAFANA_PASSWORD="TigTest$(date +%s)!"
export TIG_INFLUXDB_PORT=8086
export CONTAINER_PREFIX=test-tig
export TELEGRAF_INTERVAL=10s
export TELEGRAF_HOSTNAME="c5-4xlarge-test-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# Performance optimizations for large instance
export DOCKER_OPTS="--storage-driver=overlay2 --log-driver=json-file --log-opt max-size=10m --log-opt max-file=3"

# Enable detailed logging for testing
export LOG_FILE="/var/log/tig-stack-install.log"
export DEBUG=true

# Create a test marker file
echo "TIG Stack deployment started at $(date)" > /tmp/tig-deployment-start.txt
echo "Instance Type: c5.4xlarge" >> /tmp/tig-deployment-start.txt
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" >> /tmp/tig-deployment-start.txt
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)" >> /tmp/tig-deployment-start.txt

# Download and execute the TIG stack installation script
curl -sSL https://raw.githubusercontent.com/Alohamoras/ec2-tig-stack-userdata/main/user-data.sh | bash

# Post-installation validation and reporting
cat << 'EOF' > /tmp/post-install-check.sh
#!/bin/bash

echo "=== TIG Stack Post-Installation Check ===" | tee -a /var/log/tig-stack-install.log

# Check Docker status
echo "Docker Status:" | tee -a /var/log/tig-stack-install.log
systemctl is-active docker | tee -a /var/log/tig-stack-install.log

# Check containers
echo "Container Status:" | tee -a /var/log/tig-stack-install.log
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a /var/log/tig-stack-install.log

# Check resource usage
echo "System Resources:" | tee -a /var/log/tig-stack-install.log
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)" | tee -a /var/log/tig-stack-install.log
echo "Memory Usage: $(free -h | grep '^Mem:' | awk '{print $3 "/" $2}')" | tee -a /var/log/tig-stack-install.log
echo "Disk Usage: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')" | tee -a /var/log/tig-stack-install.log

# Test Grafana accessibility
echo "Testing Grafana accessibility:" | tee -a /var/log/tig-stack-install.log
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; then
    echo "✓ Grafana is accessible on port 3000" | tee -a /var/log/tig-stack-install.log
else
    echo "✗ Grafana is not accessible" | tee -a /var/log/tig-stack-install.log
fi

# Create completion marker
echo "TIG Stack deployment completed at $(date)" > /tmp/tig-deployment-complete.txt
echo "Total deployment time: $(($(date +%s) - $(stat -c %Y /tmp/tig-deployment-start.txt))) seconds" >> /tmp/tig-deployment-complete.txt

# Display access information
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "=== Access Information ===" | tee -a /var/log/tig-stack-install.log
echo "Grafana URL: http://$PUBLIC_IP:3000" | tee -a /var/log/tig-stack-install.log
echo "Username: admin" | tee -a /var/log/tig-stack-install.log
echo "Password: Check /opt/tig-stack/.env file" | tee -a /var/log/tig-stack-install.log
echo "SSH: ssh -i your-key.pem ec2-user@$PUBLIC_IP" | tee -a /var/log/tig-stack-install.log

EOF

chmod +x /tmp/post-install-check.sh

# Run post-installation check after a brief delay
(sleep 30 && /tmp/post-install-check.sh) &

# Send completion notification to CloudWatch Logs (if AWS CLI is available)
if command -v aws >/dev/null 2>&1; then
    aws logs create-log-group --log-group-name /aws/ec2/tig-stack-testing --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null || true
    aws logs create-log-stream --log-group-name /aws/ec2/tig-stack-testing --log-stream-name $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 2>/dev/null || true
fi