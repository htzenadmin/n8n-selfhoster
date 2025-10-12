#!/bin/bash

###################################################################################
#                                                                                 #
#                    Complete Docker Fix and N8N Install Script                  #
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

log "INFO" "Starting complete Docker fix and N8N installation..."

# Step 1: Completely remove any existing Docker installations
log "INFO" "Removing all existing Docker installations..."

# Stop any running containers
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove Snap Docker
snap remove docker 2>/dev/null || true

# Remove APT Docker
apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
apt remove -y docker.io docker-compose 2>/dev/null || true

# Kill any remaining Docker processes
pkill -f dockerd 2>/dev/null || true
pkill -f containerd 2>/dev/null || true

# Clean up Docker directories
rm -rf /var/lib/docker
rm -rf /etc/docker
rm -rf /var/run/docker*
rm -rf /run/docker*

log "SUCCESS" "Docker cleanup completed"

# Step 2: Install Docker properly
log "INFO" "Installing Docker from official repository..."

# Update package index
apt update

# Install prerequisites
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again
apt update

# Install Docker
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "SUCCESS" "Docker installed successfully"

# Step 3: Configure Docker properly
log "INFO" "Configuring Docker with proper DNS settings..."

mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# Step 4: Start Docker service
log "INFO" "Starting Docker service..."

systemctl enable docker
systemctl start docker

# Wait for Docker to start
sleep 10

# Step 5: Verify Docker installation
log "INFO" "Verifying Docker installation..."

# Check if socket exists
if [ -S /var/run/docker.sock ]; then
    log "SUCCESS" "Docker socket created successfully"
else
    log "ERROR" "Docker socket not found, checking alternative locations..."

    # Check for socket in /run
    if [ -S /run/docker.sock ]; then
        log "INFO" "Found socket at /run/docker.sock, creating symlink..."
        ln -sf /run/docker.sock /var/run/docker.sock
    else
        log "ERROR" "No Docker socket found anywhere"
        systemctl status docker
        exit 1
    fi
fi

# Test Docker
if docker version >/dev/null 2>&1; then
    log "SUCCESS" "Docker is working properly"
else
    log "ERROR" "Docker is not responding"
    systemctl status docker
    exit 1
fi

# Step 6: Add user to docker group
log "INFO" "Adding sylvester to docker group..."
usermod -aG docker sylvester || true

# Step 7: Test image pulling
log "INFO" "Testing Docker image pulling..."

if docker pull hello-world; then
    log "SUCCESS" "Docker can pull images successfully"
    docker run --rm hello-world
else
    log "ERROR" "Docker cannot pull images"

    # Show diagnostic information
    log "INFO" "Diagnostic information:"
    echo "Docker version:"
    docker version
    echo "Docker info:"
    docker info
    echo "DNS resolution test:"
    nslookup registry-1.docker.io
    exit 1
fi

# Step 8: Pull N8N images
log "INFO" "Pre-downloading N8N images..."

log "INFO" "Downloading PostgreSQL 13..."
if timeout 600 docker pull postgres:13; then
    log "SUCCESS" "PostgreSQL image downloaded"
else
    log "WARNING" "PostgreSQL download failed, will try during installation"
fi

log "INFO" "Downloading N8N latest..."
if timeout 600 docker pull n8nio/n8n:latest; then
    log "SUCCESS" "N8N image downloaded"
else
    log "WARNING" "N8N download failed, will try during installation"
fi

# Step 9: Restart previous containers (excluding Pi-hole)
log "INFO" "Restarting your other containers..."

# Start containers that were running before
containers_to_start=("portainer" "nextcloud" "uptime-kuma" "caddy" "vaultwarden")

for container in "${containers_to_start[@]}"; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        log "INFO" "Starting $container..."
        docker start "$container" || log "WARNING" "Failed to start $container"
    else
        log "INFO" "$container container not found, skipping"
    fi
done

# Step 10: Install N8N
log "INFO" "Installing N8N..."

if curl -fsSL https://raw.githubusercontent.com/sylvester-francis/n8n-selfhoster/main/install.sh | bash; then
    log "SUCCESS" "N8N installation completed successfully!"

    echo ""
    echo "==================================================================================="
    echo "🎉 Complete Installation Successful!"
    echo "==================================================================================="
    echo ""
    echo "✅ Docker fixed and working"
    echo "✅ DNS resolution working"
    echo "✅ N8N installation completed"
    echo ""
    echo "Your N8N credentials:"
    if [ -f "/opt/n8n/credentials.txt" ]; then
        cat /opt/n8n/credentials.txt
    elif [ -f "/root/n8n/credentials.txt" ]; then
        cat /root/n8n/credentials.txt
    else
        echo "Credentials file not found in expected locations"
    fi
    echo ""
    echo "Container status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "🚀 Installation complete! Your N8N instance should be accessible now."

else
    log "ERROR" "N8N installation failed"
    echo ""
    echo "But Docker is now working! You can try the N8N installation manually:"
    echo "curl -fsSL https://raw.githubusercontent.com/sylvester-francis/n8n-selfhoster/main/install.sh | sudo bash"
    echo ""
    echo "Or check the container status:"
    docker ps -a
    exit 1
fi