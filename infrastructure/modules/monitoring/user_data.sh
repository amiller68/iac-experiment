#!/bin/bash
set -e

# Update system
yum update -y
yum install -y docker amazon-cloudwatch-agent

# Start and enable docker
systemctl start docker
systemctl enable docker

# Create directories
mkdir -p /monitoring/prometheus
mkdir -p /monitoring/grafana
mkdir -p /etc/prometheus
mkdir -p /etc/grafana/provisioning/{datasources,dashboards}

# Mount EBS volume
mkfs -t xfs /dev/xvdf
mount /dev/xvdf /monitoring
echo "/dev/xvdf /monitoring xfs defaults,nofail 0 2" >> /etc/fstab

# Create Prometheus config
cat > /etc/prometheus/prometheus.yml <<'EOF'
${prometheus_config}
EOF

# Create Grafana datasource config
cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'EOF'
${grafana_datasource_config}
EOF

# Create Grafana dashboard config
cat > /etc/grafana/provisioning/dashboards/dashboards.yaml <<'EOF'
${grafana_dashboard_config}
EOF

# Create default dashboard
cat > /etc/grafana/provisioning/dashboards/request-metrics.json <<'EOF'
${grafana_dashboard}
EOF

# Start Prometheus
docker run -d \
  --name prometheus \
  --restart=unless-stopped \
  -p 9090:9090 \
  -v /monitoring/prometheus:/prometheus \
  -v /etc/prometheus:/etc/prometheus \
  --user root \
  prom/prometheus:v2.42.0

# Start Grafana
docker run -d \
  --name grafana \
  --restart=unless-stopped \
  -p 3000:3000 \
  -v /monitoring/grafana:/var/lib/grafana \
  -v /etc/grafana/provisioning:/etc/grafana/provisioning \
  -e "GF_SECURITY_ADMIN_PASSWORD=${grafana_admin_password}" \
  -e "GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel" \
  -e "GF_AUTH_ANONYMOUS_ENABLED=false" \
  -e "GF_SECURITY_ALLOW_EMBEDDING=true" \
  grafana/grafana:9.5.2 