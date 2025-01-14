#!/bin/bash
set -e

# Install required packages
yum update -y
yum install -y docker aws-cli jq

# Start and enable docker
systemctl start docker
systemctl enable docker

# Create monitoring directories on root volume
mkdir -p /monitoring/prometheus
mkdir -p /monitoring/grafana

# Get Grafana password from Secrets Manager
GRAFANA_PASSWORD=$(aws secretsmanager get-secret-value \
  --region ${aws_region} \
  --secret-id ${grafana_admin_secret_arn} \
  --query SecretString --output text)

# Create Grafana config directories
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/provisioning/datasources

# Configure Prometheus
mkdir -p /etc/prometheus
cat > /etc/prometheus/prometheus.yml <<'EOF'
${prometheus_config}
EOF

# Start Prometheus
docker run -d \
  --name prometheus \
  --restart=unless-stopped \
  -p 9090:9090 \
  -v /etc/prometheus:/etc/prometheus \
  -v /monitoring/prometheus:/prometheus \
  prom/prometheus:v2.42.0

# Start Grafana
docker run -d \
  --name grafana \
  --restart=unless-stopped \
  -p 3000:3000 \
  -e "GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD" \
  -e "GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel" \
  -v /etc/grafana/provisioning:/etc/grafana/provisioning \
  -v /monitoring/grafana:/var/lib/grafana \
  grafana/grafana:9.5.2 