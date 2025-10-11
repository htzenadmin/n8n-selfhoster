#!/bin/bash

###################################################################################
#                                                                                 #
#                        N8N Self-Hosted Installer                               #
#                        N8N Setup Module                                         #
#                                                                                 #
###################################################################################

# Set up N8N with PostgreSQL
setup_n8n() {
    show_progress 7 15 "Setting up N8N with PostgreSQL"

    # Verify required variables are set
    if [ -z "${DB_PASSWORD:-}" ]; then
        log "ERROR" "DB_PASSWORD is not set"
        return 1
    fi

    if [ -z "${ADMIN_PASSWORD:-}" ]; then
        log "ERROR" "ADMIN_PASSWORD is not set"
        return 1
    fi

    if [ -z "${DOMAIN_NAME:-}" ]; then
        log "ERROR" "DOMAIN_NAME is not set"
        return 1
    fi

    if [ -z "${TIMEZONE:-}" ]; then
        log "WARNING" "TIMEZONE is not set, using UTC"
        export TIMEZONE="UTC"
    fi

    if [ -z "${N8N_DIR:-}" ]; then
        log "ERROR" "N8N_DIR is not set"
        return 1
    fi

    log "INFO" "Configuration variables verified"
    log "DEBUG" "Using domain: $DOMAIN_NAME"
    log "DEBUG" "Using timezone: $TIMEZONE"
    log "DEBUG" "N8N directory: $N8N_DIR"

    # Format the webhook URL properly for IPv6 addresses
    local webhook_url
    if [[ "$DOMAIN_NAME" =~ : ]]; then
        # IPv6 address - wrap in brackets
        webhook_url="https://[$DOMAIN_NAME]/"
        log "INFO" "Detected IPv6 address, using bracketed format: $webhook_url"
    else
        # Regular domain or IPv4 address
        webhook_url="https://$DOMAIN_NAME/"
        log "INFO" "Using standard URL format: $webhook_url"
    fi

    # Additional debug: Show what will be written to the file
    log "INFO" "WEBHOOK_URL that will be written: $webhook_url"

    # Create N8N directory
    mkdir -p "$N8N_DIR"
    cd "$N8N_DIR" || exit

    # Create docker-compose.yml
    log "INFO" "Creating N8N configuration..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  postgres:
    image: postgres:13
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: $DB_PASSWORD
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -U n8n -d n8n"]
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=$DB_PASSWORD
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=$ADMIN_PASSWORD
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - "WEBHOOK_URL=$webhook_url"
      - NODE_ENV=production
      - GENERIC_TIMEZONE=$TIMEZONE
      - N8N_LOG_LEVEL=info
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
  n8n_data:
EOF
    
    # Save credentials
    cat > credentials.txt << EOF
N8N Installation Credentials
============================
Date: $(date)
Server: $DOMAIN_NAME

Database Password: $DB_PASSWORD
Admin Username: admin
Admin Password: $ADMIN_PASSWORD

Access URL: $webhook_url
Direct URL: ${webhook_url%/}:5678 (if needed)

IMPORTANT: Save these credentials securely and delete this file after copying!
EOF
    
    chmod 600 credentials.txt
    
    log "SUCCESS" "N8N configuration created"
    log "INFO" "Credentials saved to $N8N_DIR/credentials.txt"

    # Debug: Verify file was created successfully
    if [ -f "docker-compose.yml" ]; then
        log "INFO" "docker-compose.yml created successfully"
        log "INFO" "File size: $(wc -c < docker-compose.yml) bytes"
        log "INFO" "First few lines:"
        head -n 5 docker-compose.yml
    else
        log "ERROR" "docker-compose.yml was not created!"
        return 1
    fi
}