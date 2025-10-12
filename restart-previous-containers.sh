#!/bin/bash

###################################################################################
#                                                                                 #
#                    Restart Previously Running Docker Containers                #
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

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    log "ERROR" "Docker is not running or not accessible"
    log "INFO" "Please ensure Docker is installed and running first"
    exit 1
fi

log "INFO" "Scanning for previously running containers..."

# Get all containers (running and stopped)
containers=$(docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Image}}")

if [ -z "$containers" ]; then
    log "WARNING" "No containers found"
    exit 0
fi

echo ""
log "INFO" "Found containers:"
echo -e "${BLUE}NAME\t\t\tSTATUS\t\t\tIMAGE${NC}"
echo "==================================================================================="
echo "$containers"
echo ""

# Get stopped containers that were previously running
stopped_containers=$(docker ps -a --filter "status=exited" --format "{{.Names}}")

if [ -z "$stopped_containers" ]; then
    log "SUCCESS" "All containers are already running!"
    echo ""
    log "INFO" "Current running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 0
fi

log "INFO" "Found stopped containers that can be restarted:"
echo "$stopped_containers"
echo ""

# Ask for confirmation if running interactively
if [ -t 0 ]; then
    echo -n "Do you want to restart all stopped containers? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
fi

# Restart each stopped container
log "INFO" "Restarting stopped containers..."
echo ""

restart_count=0
success_count=0
failed_containers=()

for container in $stopped_containers; do
    log "INFO" "Starting $container..."

    if docker start "$container" >/dev/null 2>&1; then
        log "SUCCESS" "$container started successfully"
        ((success_count++))
    else
        log "ERROR" "Failed to start $container"
        failed_containers+=("$container")
    fi

    ((restart_count++))
    sleep 1  # Brief pause between starts
done

echo ""
echo "==================================================================================="
log "INFO" "Restart Summary:"
echo "  Total containers processed: $restart_count"
echo "  Successfully started: $success_count"
echo "  Failed to start: ${#failed_containers[@]}"

if [ ${#failed_containers[@]} -gt 0 ]; then
    echo ""
    log "WARNING" "Containers that failed to start:"
    for container in "${failed_containers[@]}"; do
        echo "  - $container"
        log "INFO" "Checking logs for $container:"
        docker logs --tail=5 "$container" 2>&1 | sed 's/^/    /'
        echo ""
    done
fi

echo ""
log "INFO" "Current container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
log "INFO" "All stopped containers processed!"

# Check for any containers still stopped
still_stopped=$(docker ps -a --filter "status=exited" --format "{{.Names}}")
if [ -n "$still_stopped" ]; then
    echo ""
    log "WARNING" "Some containers are still stopped:"
    echo "$still_stopped"
    echo ""
    log "INFO" "You can check individual container logs with:"
    echo "  docker logs <container_name>"
    echo ""
    log "INFO" "Or try starting individual containers with:"
    echo "  docker start <container_name>"
else
    echo ""
    log "SUCCESS" "All containers are now running!"
fi

# Show resource usage
echo ""
log "INFO" "Docker system resource usage:"
docker system df