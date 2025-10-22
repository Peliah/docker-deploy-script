# Ursulaonyi
# ursulaonyi
# Online





# Text Channel
# Ursulaonyi's server:deployscript
# Search

# deployscript chat
# Welcome to #deployscript!
# This is the start of the #deployscript channel. 

# Edit Channel
# October 21, 2025

# Ursulaonyi — Yesterday at 2:13 PMTuesday, October 21, 2025 at 2:13 PM
#!/bin/bash

# ============================================================
# Automated Deployment Script
# ============================================================
# This script automates the deployment of a containerized
Expand
Expand (459 lines)
View whole file
message.txt
message.txt (16 KB)
16 KB
message.txt (16 KB)
Download message.txt (16 KB)Change language
:thumbsup:
Click to react
:heart:
Click to react
:100:
Click to react
Add Reaction
Edit
Forward
More

Message #deployscript
﻿
Halloween haunts your Discord!
Beware... your notification sounds have a chilling twist. Head to your settings if you dare to switch back.
#!/bin/bash

# ============================================================
# Automated Deployment Script
# ============================================================
# This script automates the deployment of a containerized
# application to a remote server using Docker and Nginx
# ============================================================

set -euo pipefail

# ============================================================
# LOGGING CONFIGURATION
# ============================================================
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_warning() {
    log "WARNING" "$@"
}

# ============================================================
# ERROR HANDLING
# ============================================================
error_exit() {
    log_error "$1"
    exit 1
}

trap 'error_exit "Script failed at line $LINENO"' ERR

# ============================================================
# CLEANUP FUNCTION
# ============================================================
cleanup() {
    log_info "Starting cleanup process..."
    
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        log_info "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "$SSH_KEY_PATH" ]; then
        log_info "Cleaning up temporary SSH key"
        rm -f "$SSH_KEY_PATH"
    fi
    
    log_success "Cleanup completed"
}

trap cleanup EXIT

# ============================================================
# INPUT VALIDATION FUNCTIONS
# ============================================================
validate_url() {
    local url=$1
    if [[ ! $url =~ ^https?:// ]]; then
        error_exit "Invalid Git repository URL format"
    fi
}

validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Invalid IP address format"
    fi
}

validate_port() {
    local port=$1
    if [[ ! $port =~ ^[0-9]+$ ]] || [ $port -lt 1 ] || [ $port -gt 65535 ]; then
        error_exit "Invalid port number. Must be between 1 and 65535"
    fi
}

# ============================================================
# USER INPUT COLLECTION
# ============================================================
log_info "Starting deployment script..."
log_info "Collecting deployment information..."

read -p "Enter Git repository URL: " GIT_REPO_URL
validate_url "$GIT_REPO_URL"
log_info "Git repository URL validated"

read -sp "Enter Personal Access Token (optional, press Enter to skip): " GIT_TOKEN
echo
if [ -n "$GIT_TOKEN" ]; then
    log_info "Personal Access Token provided"
fi

read -p "Enter target server IP address: " SERVER_IP
validate_ip "$SERVER_IP"
log_info "Server IP validated: $SERVER_IP"

read -p "Enter SSH username: " SSH_USER
log_info "SSH username: $SSH_USER"

read -p "Enter SSH port [default: 22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
validate_port "$SSH_PORT"

read -p "Enter path to SSH private key: " SSH_KEY_PATH
if [ ! -f "$SSH_KEY_PATH" ]; then
    error_exit "SSH key file not found: $SSH_KEY_PATH"
fi
log_info "SSH key validated"

read -p "Enter application port [default: 3000]: " APP_PORT
APP_PORT=${APP_PORT:-3000}
validate_port "$APP_PORT"

read -p "Enter application name [default: app]: " APP_NAME
APP_NAME=${APP_NAME:-app}

read -p "Enter branch name [default: main]: " BRANCH_NAME
BRANCH_NAME=${BRANCH_NAME:-main}

log_success "All inputs collected and validated"

# ============================================================
# SSH CONNECTIVITY CHECK
# ============================================================
log_info "Testing SSH connectivity to $SERVER_IP..."

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes -i "$SSH_KEY_PATH" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'" &>/dev/null; then
    error_exit "SSH connectivity test failed. Please check your credentials and network connection"
fi

log_success "SSH connectivity verified"

# ============================================================
# GIT OPERATIONS
# ============================================================
TEMP_DIR=$(mktemp -d)
REPO_DIR="$TEMP_DIR/$(basename "$GIT_REPO_URL" .git)"

log_info "Cloning repository to temporary directory..."

# Handle existing repository
if [ -d "$REPO_DIR" ]; then
    log_warning "Repository directory already exists, removing..."
    rm -rf "$REPO_DIR"
fi

# Clone with or without token
if [ -n "$GIT_TOKEN" ]; then
    GIT_URL_WITH_TOKEN=$(echo "$GIT_REPO_URL" | sed "s|https://|https://$GIT_TOKEN@|")
    git clone "$GIT_URL_WITH_TOKEN" "$REPO_DIR" &>> "$LOG_FILE" || error_exit "Git clone failed"
else
    git clone "$GIT_REPO_URL" "$REPO_DIR" &>> "$LOG_FILE" || error_exit "Git clone failed"
fi

log_success "Repository cloned successfully"

# Switch to specified branch
log_info "Switching to branch: $BRANCH_NAME"
cd "$REPO_DIR"
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME" &>> "$LOG_FILE" || error_exit "Branch checkout failed"
    log_success "Switched to branch: $BRANCH_NAME"
else
    log_warning "Branch $BRANCH_NAME not found, using current branch"
fi

# ============================================================
# SSH COMMAND EXECUTION WRAPPER
# ============================================================
ssh_execute() {
    local command=$1
    ssh -i "$SSH_KEY_PATH" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" "$command"
}

# ============================================================
# SERVER PREPARATION
# ============================================================
log_info "Preparing server environment..."

# Update package lists
log_info "Updating package lists..."
ssh_execute "sudo apt-get update -y" &>> "$LOG_FILE" || log_warning "Package update encountered issues"

# Install Docker if not present
log_info "Checking Docker installation..."
if ! ssh_execute "command -v docker" &>/dev/null; then
    log_info "Installing Docker..."
    ssh_execute "curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh" &>> "$LOG_FILE" || error_exit "Docker installation failed"
    log_success "Docker installed successfully"
else
    log_info "Docker is already installed"
fi

# Install Nginx if not present
log_info "Checking Nginx installation..."
if ! ssh_execute "command -v nginx" &>/dev/null; then
    log_info "Installing Nginx..."
    ssh_execute "sudo apt-get install -y nginx" &>> "$LOG_FILE" || error_exit "Nginx installation failed"
    log_success "Nginx installed successfully"
else
    log_info "Nginx is already installed"
fi

# Configure Docker group
log_info "Configuring Docker permissions..."
ssh_execute "sudo usermod -aG docker $SSH_USER" &>> "$LOG_FILE" || log_warning "Docker group configuration encountered issues"

# Start and enable services
log_info "Starting services..."
ssh_execute "sudo systemctl start docker && sudo systemctl enable docker" &>> "$LOG_FILE" || log_warning "Docker service start encountered issues"
ssh_execute "sudo systemctl start nginx && sudo systemctl enable nginx" &>> "$LOG_FILE" || log_warning "Nginx service start encountered issues"

log_success "Server preparation completed"

# ============================================================
# DOCKER SERVICE CHECK
# ============================================================
log_info "Verifying Docker service status..."
if ! ssh_execute "sudo systemctl is-active --quiet docker"; then
    error_exit "Docker service is not running"
fi
log_success "Docker service is running"

# ============================================================
# FILE TRANSFER
# ============================================================
log_info "Transferring application files to server..."
REMOTE_APP_DIR="/home/$SSH_USER/$APP_NAME"

ssh_execute "mkdir -p $REMOTE_APP_DIR" || error_exit "Failed to create remote directory"

scp -i "$SSH_KEY_PATH" -P "$SSH_PORT" -r "$REPO_DIR"/* "$SSH_USER@$SERVER_IP:$REMOTE_APP_DIR/" &>> "$LOG_FILE" || error_exit "File transfer failed"

log_success "Files transferred successfully"

# ============================================================
# DOCKER DEPLOYMENT
# ============================================================
log_info "Starting Docker deployment..."

# Stop and remove existing container (idempotent)
log_info "Checking for existing containers..."
if ssh_execute "docker ps -aq -f name=$APP_NAME" 2>/dev/null | grep -q .; then
    log_info "Stopping and removing existing container..."
    ssh_execute "docker stop $APP_NAME && docker rm $APP_NAME" &>> "$LOG_FILE" || log_warning "Container removal encountered issues"
    log_success "Existing container removed"
else
    log_info "No existing container found"
fi

# Remove old image (idempotent)
if ssh_execute "docker images -q $APP_NAME" 2>/dev/null | grep -q .; then
    log_info "Removing old image..."
    ssh_execute "docker rmi $APP_NAME" &>> "$LOG_FILE" || log_warning "Image removal encountered issues"
fi

# Build Docker image
log_info "Building Docker image..."
ssh_execute "cd $REMOTE_APP_DIR && docker build -t $APP_NAME ." &>> "$LOG_FILE" || error_exit "Docker build failed"
log_success "Docker image built successfully"

# Run Docker container
log_info "Starting Docker container..."
ssh_execute "docker run -d --name $APP_NAME --restart unless-stopped -p $APP_PORT:$APP_PORT $APP_NAME" &>> "$LOG_FILE" || error_exit "Docker container start failed"
log_success "Docker container started successfully"

# ============================================================
# CONTAINER HEALTH CHECK
# ============================================================
log_info "Performing container health checks..."

# Wait for container to stabilize
sleep 5

# Check if container is running
if ! ssh_execute "docker ps -f name=$APP_NAME --format '{{.Status}}'" | grep -q "Up"; then
    log_error "Container health check failed - container is not running"
    ssh_execute "docker logs $APP_NAME" &>> "$LOG_FILE"
    error_exit "Container failed to start properly"
fi

log_success "Container is running"

# Check container logs for errors
log_info "Checking container logs..."
CONTAINER_LOGS=$(ssh_execute "docker logs $APP_NAME 2>&1 | tail -20")
if echo "$CONTAINER_LOGS" | grep -qi "error\|exception\|fatal"; then
    log_warning "Potential errors found in container logs"
    echo "$CONTAINER_LOGS" >> "$LOG_FILE"
else
    log_success "No critical errors found in container logs"
fi

# Test application endpoint
log_info "Testing application endpoint..."
sleep 3
if ssh_execute "curl -f http://localhost:$APP_PORT/health" &>/dev/null; then
    log_success "Application health check passed"
else
    log_warning "Application health endpoint not responding (this may be normal if no health endpoint exists)"
fi

# ============================================================
# NGINX CONFIGURATION
# ============================================================
log_info "Configuring Nginx reverse proxy..."

NGINX_CONFIG="/etc/nginx/sites-available/$APP_NAME"

# Create comprehensive Nginx configuration
ssh_execute "sudo tee $NGINX_CONFIG > /dev/null << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_IP;

    # Security headers
    add_header X-Frame-Options \"SAMEORIGIN\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;

    # Logging
    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # SSL configuration placeholder (uncomment when certificate is available)
    # listen 443 ssl http2;
    # listen [::]:443 ssl http2;
    # ssl_certificate /etc/ssl/certs/${APP_NAME}.crt;
    # ssl_certificate_key /etc/ssl/private/${APP_NAME}.key;
    # ssl_protocols TLSv1.2 TLSv1.3;
    # ssl_ciphers HIGH:!aNULL:!MD5;
}
EOF
" || error_exit "Nginx configuration creation failed"

log_success "Nginx configuration created"

# Enable site (idempotent)
log_info "Enabling Nginx site..."
ssh_execute "sudo ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/$APP_NAME" || error_exit "Failed to enable Nginx site"

# Remove default site if it conflicts
if ssh_execute "test -L /etc/nginx/sites-enabled/default"; then
    log_info "Removing default Nginx site to prevent conflicts..."
    ssh_execute "sudo rm /etc/nginx/sites-enabled/default" || log_warning "Could not remove default site"
fi

# Test Nginx configuration
log_info "Testing Nginx configuration..."
if ! ssh_execute "sudo nginx -t" &>> "$LOG_FILE"; then
    error_exit "Nginx configuration test failed"
fi
log_success "Nginx configuration is valid"

# Reload Nginx
log_info "Reloading Nginx..."
ssh_execute "sudo systemctl reload nginx" &>> "$LOG_FILE" || error_exit "Nginx reload failed"
log_success "Nginx reloaded successfully"

# ============================================================
# DEPLOYMENT VALIDATION
# ============================================================
log_info "Validating deployment..."

# Check Nginx status
log_info "Checking Nginx service status..."
if ! ssh_execute "sudo systemctl is-active --quiet nginx"; then
    error_exit "Nginx service is not running"
fi
log_success "Nginx is running"

# Check Docker service status
log_info "Checking Docker service status..."
if ! ssh_execute "sudo systemctl is-active --quiet docker"; then
    error_exit "Docker service is not running"
fi
log_success "Docker service is running"

# Comprehensive container check
log_info "Performing comprehensive container validation..."
CONTAINER_INFO=$(ssh_execute "docker inspect $APP_NAME --format '{{.State.Status}} {{.State.Running}} {{.RestartCount}}'")
log_info "Container info: $CONTAINER_INFO"

if ! echo "$CONTAINER_INFO" | grep -q "running true"; then
    error_exit "Container validation failed"
fi
log_success "Container validation passed"

# Final endpoint test
log_info "Performing final endpoint test..."
sleep 2
if curl -f -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP" | grep -q "200\|301\|302"; then
    log_success "Application is accessible via Nginx"
else
    log_warning "Could not verify application accessibility (may require specific endpoint)"
fi

# ============================================================
# DEPLOYMENT SUMMARY
# ============================================================
log_success "=============================================="
log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
log_success "=============================================="
log_info "Application: $APP_NAME"
log_info "Server: $SERVER_IP"
log_info "Application Port: $APP_PORT"
log_info "Branch: $BRANCH_NAME"
log_info "Access URL: http://$SERVER_IP"
log_info "Docker Container: $APP_NAME"
log_info "Log file: $LOG_FILE"
log_success "=============================================="

log_info "You can check the application with:"
log_info "  curl http://$SERVER_IP"
log_info ""
log_info "View container logs with:"
log_info "  ssh -i $SSH_KEY_PATH -p $SSH_PORT $SSH_USER@$SERVER_IP 'docker logs $APP_NAME'"
log_info ""
log_info "Check container status with:"
log_info "  ssh -i $SSH_KEY_PATH -p $SSH_PORT $SSH_USER@$SERVER_IP 'docker ps -f name=$APP_NAME'"

exit 0
message.txt
message.txt (16 KB)
16 KB