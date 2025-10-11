#!/bin/bash

###################################################################################
#                                                                                 #
#                    DNS Fix and N8N Installation Script                         #
#                                                                                 #
###################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${BLUE}ℹ️ ${message}${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ ${message}${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️ ${message}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ ${message}${NC}"
            ;;
    esac
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "This script must be run as root (use sudo)"
    exit 1
fi

log "INFO" "Starting DNS fix and N8N installation..."

# Step 1: Configure Docker DNS
log "INFO" "Configuring Docker to use Google DNS..."

mkdir -p /etc/docker

cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

log "SUCCESS" "Docker DNS configuration created"

# Step 2: Restart Docker
log "INFO" "Restarting Docker service..."
systemctl restart docker

log "INFO" "Waiting for Docker to start..."
sleep 15

# Verify Docker is running
if systemctl is-active --quiet docker; then
    log "SUCCESS" "Docker is running"
else
    log "ERROR" "Docker failed to start"
    exit 1
fi

# Step 3: Test DNS resolution
log "INFO" "Testing DNS resolution..."

if docker run --rm busybox nslookup registry-1.docker.io >/dev/null 2>&1; then
    log "SUCCESS" "DNS resolution working"
else
    log "WARNING" "DNS test failed, but continuing..."
fi

# Step 4: Pre-download images
log "INFO" "Pre-downloading Docker images..."

log "INFO" "Downloading PostgreSQL 13 image..."
if timeout 600 docker pull postgres:13; then
    log "SUCCESS" "PostgreSQL image downloaded"
else
    log "WARNING" "PostgreSQL image download failed"
fi

log "INFO" "Downloading N8N image..."
if timeout 600 docker pull n8nio/n8n:latest; then
    log "SUCCESS" "N8N image downloaded"
else
    log "WARNING" "N8N image download failed"
fi

# Step 5: Run the N8N installation
log "INFO" "Running N8N installation..."

if curl -fsSL https://raw.githubusercontent.com/sylvester-francis/n8n-selfhoster/main/install.sh | bash; then
    log "SUCCESS" "N8N installation completed successfully!"

    # Show access information
    echo ""
    echo "==================================================================================="
    echo "🎉 N8N Installation Complete!"
    echo "==================================================================================="
    echo ""
    echo "Your N8N instance should now be running. Check the credentials file:"
    echo "sudo cat /root/n8n/credentials.txt"
    echo ""
    echo "If the installation is in /opt/n8n instead:"
    echo "sudo cat /opt/n8n/credentials.txt"
    echo ""
    echo "Container status:"
    docker ps --filter name=n8n --filter name=postgres --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""

else
    log "ERROR" "N8N installation failed"
    echo ""
    echo "Troubleshooting information:"
    echo "- Docker status: $(systemctl is-active docker)"
    echo "- DNS configuration: /etc/docker/daemon.json"
    echo "- Container logs: docker logs n8n-postgres"
    echo ""
    exit 1
fi