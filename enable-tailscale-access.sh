#!/bin/bash

###################################################################################
#                                                                                 #
#                    Enable Tailscale Access for N8N                            #
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

log "INFO" "Configuring N8N for Tailscale access..."

# Step 1: Check current configuration
log "INFO" "Checking current N8N configuration..."

N8N_DIR="/opt/n8n"
if [ ! -f "$N8N_DIR/docker-compose.yml" ]; then
    log "ERROR" "N8N docker-compose.yml not found at $N8N_DIR"
    exit 1
fi

# Step 2: Check Tailscale status
log "INFO" "Checking Tailscale configuration..."
if ! command -v tailscale >/dev/null 2>&1; then
    log "ERROR" "Tailscale is not installed"
    exit 1
fi

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
if [ -z "$TAILSCALE_IP" ]; then
    log "ERROR" "Could not get Tailscale IP address"
    tailscale status
    exit 1
fi

log "SUCCESS" "Tailscale IP found: $TAILSCALE_IP"

# Step 3: Show current port binding
log "INFO" "Current port binding:"
netstat -tlnp | grep :5678 || log "WARNING" "N8N port 5678 not found"

# Step 4: Backup current configuration
log "INFO" "Backing up current docker-compose.yml..."
cp "$N8N_DIR/docker-compose.yml" "$N8N_DIR/docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"

# Step 5: Update docker-compose.yml for external access
log "INFO" "Updating docker-compose.yml for Tailscale access..."

cd "$N8N_DIR"

# Stop containers first
log "INFO" "Stopping N8N containers..."
docker-compose down

# Restore from backup if previous attempt failed
if [ -f "docker-compose.yml.backup."* ]; then
    log "INFO" "Restoring from backup..."
    cp docker-compose.yml.backup.* docker-compose.yml
fi

# Make targeted changes to the existing working configuration
log "INFO" "Making targeted configuration changes..."

# Change port binding from localhost to all interfaces
sed -i 's/"127.0.0.1:5678:5678"/"0.0.0.0:5678:5678"/g' docker-compose.yml

# Change protocol from HTTPS to HTTP for Tailscale
sed -i 's/N8N_PROTOCOL=https/N8N_PROTOCOL=http/g' docker-compose.yml

# Update webhook URL for Tailscale IP
sed -i "s|WEBHOOK_URL=https://\[2607:fea8:1fdd:e520::c56c\]/|WEBHOOK_URL=http://$TAILSCALE_IP:5678/|g" docker-compose.yml

# Ensure N8N_HOST is set correctly (should already be 0.0.0.0)
sed -i 's/N8N_HOST=127.0.0.1/N8N_HOST=0.0.0.0/g' docker-compose.yml

log "SUCCESS" "Configuration updated successfully"

# Step 6: Start containers with new configuration
log "INFO" "Starting N8N with new configuration..."
docker-compose up -d

# Step 7: Wait for services to start
log "INFO" "Waiting for services to start..."
sleep 10

# Step 8: Verify the configuration
log "INFO" "Verifying new configuration..."

# Check port binding
log "INFO" "New port binding:"
netstat -tlnp | grep :5678

# Check container status
log "INFO" "Container status:"
docker-compose ps

# Test local access
log "INFO" "Testing local access..."
if curl -s http://localhost:5678 >/dev/null; then
    log "SUCCESS" "N8N is responding on localhost"
else
    log "WARNING" "N8N is not responding on localhost yet"
fi

# Test Tailscale access
log "INFO" "Testing Tailscale access..."
if curl -s --connect-timeout 5 http://$TAILSCALE_IP:5678 >/dev/null; then
    log "SUCCESS" "N8N is accessible via Tailscale!"
else
    log "WARNING" "N8N may not be accessible via Tailscale yet (still starting up)"
fi

# Step 9: Show access information
echo ""
echo "==================================================================================="
log "SUCCESS" "N8N Tailscale Configuration Complete!"
echo "==================================================================================="
echo ""
log "INFO" "Access Information:"
echo "  🌐 Tailscale URL: http://$TAILSCALE_IP:5678"
echo "  🏠 Local URL: http://localhost:5678"
echo ""
log "INFO" "Login Credentials:"
ADMIN_PASSWORD=$(grep "N8N_BASIC_AUTH_PASSWORD=" "$N8N_DIR/docker-compose.yml" | cut -d'=' -f2)
echo "  👤 Username: admin"
echo "  🔑 Password: $ADMIN_PASSWORD"
echo ""
log "INFO" "Notes:"
echo "  • Access from any device on your Tailscale network"
echo "  • No SSH tunnel required"
echo "  • Configuration backup saved as docker-compose.yml.backup.*"
echo ""

# Step 10: Show container logs if there are issues
if ! curl -s --connect-timeout 10 http://$TAILSCALE_IP:5678 >/dev/null; then
    log "WARNING" "N8N doesn't seem to be responding via Tailscale yet"
    log "INFO" "Checking N8N container logs..."
    echo ""
    docker logs n8n --tail=10
    echo ""
    log "INFO" "If you see errors above, try restarting:"
    echo "  cd $N8N_DIR && sudo docker-compose restart"
fi

log "SUCCESS" "Configuration complete! Try accessing: http://$TAILSCALE_IP:5678"