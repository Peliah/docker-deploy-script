#!/bin/bash

# deploy.sh - Dockerized Application Deployment Script
# Section 1: Parameter Collection and Validation
# Section 2: Repository Cloning
# Section 3: Navigate and Verify Docker Files
# Section 4: SSH into Remote Server (Connectivity Only)
# Section 5: Prepare Remote Environment

set -e  # Exit on any error

# Logging setup
LOG_FILE="deployment.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Validation functions
validate_git_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https://.+\.git$ ]] && [[ ! "$url" =~ ^git@.+\.git$ ]]; then
        log_error "Invalid Git repository URL format. Must be HTTPS (https://...git) or SSH (git@...git) format."
        return 1
    fi
    return 0
}

validate_pat() {
    local pat="$1"
    if [[ -z "$pat" || ${#pat} -lt 10 ]]; then
        log_error "Personal Access Token appears to be invalid (too short or empty)"
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid IP address format"
        return 1
    fi
    return 0
}

validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number. Must be between 1 and 65535"
        return 1
    fi
    return 0
}

validate_ssh_key() {
    local key_path="$1"
    if [ ! -f "$key_path" ]; then
        log_error "SSH key file not found: $key_path"
        return 1
    fi
    
    if [ ! -r "$key_path" ]; then
        log_error "SSH key file is not readable: $key_path"
        return 1
    fi
    
    # Check if it's a valid private key
    if ! ssh-keygen -l -f "$key_path" &>/dev/null; then
        log_error "File does not appear to be a valid SSH private key: $key_path"
        return 1
    fi
    return 0
}

# Function to prompt with validation
prompt_with_validation() {
    local prompt_text="$1"
    local validation_func="$2"
    local var_name="$3"
    local is_secret="$4"
    
    while true; do
        if [ "$is_secret" = "true" ]; then
            read -s -p "$prompt_text" value
            echo
        else
            read -p "$prompt_text" value
        fi
        
        if $validation_func "$value"; then
            eval "$var_name=\"$value\""
            break
        else
            log_warning "Validation failed. Please try again."
        fi
    done
}

# Global variables
REPO_DIR=""
CLONE_DIR=""

# Section 1: Parameter Collection
collect_parameters() {
    log "Starting parameter collection..."
    echo "=========================================="
    echo "  Dockerized Application Deployment"
    echo "  Section 1: Parameter Collection"
    echo "=========================================="
    echo
    
    # Git Repository URL
    prompt_with_validation "Git Repository URL: " validate_git_url GIT_REPO_URL false
    log_success "Git URL validated"
    
    # Personal Access Token
    echo
    echo "Note: Your PAT will be hidden while typing"
    prompt_with_validation "Personal Access Token (PAT): " validate_pat GIT_PAT true
    log_success "PAT validated"
    
    # Branch name (optional)
    echo
    read -p "Branch name [default: main]: " BRANCH_NAME
    BRANCH_NAME=${BRANCH_NAME:-main}
    log "Using branch: $BRANCH_NAME"
    
    # Remote server details
    echo
    log "Remote Server SSH Details:"
    read -p "SSH Username: " SSH_USERNAME
    if [ -z "$SSH_USERNAME" ]; then
        log_error "SSH Username cannot be empty"
        exit 1
    fi
    
    prompt_with_validation "Server IP address: " validate_ip SERVER_IP false
    log_success "IP address validated"
    
    # SSH key path with validation
    while true; do
        read -p "SSH key path [default: ~/.ssh/id_rsa]: " key_path
        key_path=${key_path:-~/.ssh/id_rsa}
        # Expand ~ to full path
        key_path="${key_path/#\~/$HOME}"
        
        if validate_ssh_key "$key_path"; then
            SSH_KEY_PATH="$key_path"
            log_success "SSH key validated"
            break
        else
            log_warning "Please provide a valid SSH key path"
        fi
    done
    
    # Application port
    echo
    prompt_with_validation "Application port (internal container port): " validate_port APP_PORT false
    log_success "Port validated"
    
    # Display summary
    echo
    log "Parameter Collection Complete:"
    echo "------------------------------------------"
    log "Git Repository: $GIT_REPO_URL"
    log "Branch: $BRANCH_NAME"
    log "SSH Username: $SSH_USERNAME"
    log "Server IP: $SERVER_IP"
    log "SSH Key: $SSH_KEY_PATH"
    log "App Port: $APP_PORT"
    echo "------------------------------------------"
    
    # Confirm parameters
    # echo
    # read -p "Are these parameters correct? (y/n): " confirm
    # if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    #     log_warning "Parameter collection cancelled by user"
    #     exit 1
    # fi
    
    log_success "All parameters collected and validated successfully"
}

# Export variables for use in other parts of the script
export_parameters() {
    export GIT_REPO_URL
    export GIT_PAT
    export BRANCH_NAME
    export SSH_USERNAME
    export SERVER_IP
    export SSH_KEY_PATH
    export APP_PORT
}

# Section 2: Repository Cloning
clone_repository() {
    log "Starting Section 2: Repository Cloning"
    echo "=========================================="
    echo "  Section 2: Repository Cloning"
    echo "=========================================="
    
    # Extract repository name from URL for folder name
    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    CLONE_DIR="$PWD/$REPO_NAME"
    
    log "Repository name: $REPO_NAME"
    log "Target directory: $CLONE_DIR"
    
    # Prepare Git credentials
    # For HTTPS URLs, embed PAT in the URL
    if [[ "$GIT_REPO_URL" =~ ^https:// ]]; then
        # Insert PAT into the Git URL
        AUTH_GIT_URL=$(echo "$GIT_REPO_URL" | sed "s|https://|https://token:${GIT_PAT}@|")
    else
        # For SSH URLs, use the original URL (PAT not needed)
        AUTH_GIT_URL="$GIT_REPO_URL"
        log "Using SSH URL - ensure SSH key is configured for Git access"
    fi
    
    # Check if repository directory already exists
    if [ -d "$CLONE_DIR" ]; then
        log "Repository directory already exists. Pulling latest changes..."
        
        cd "$CLONE_DIR"
        
        # Check if this is actually a git repository
        if [ ! -d ".git" ]; then
            log_error "Directory exists but is not a Git repository: $CLONE_DIR"
            log "Removing existing directory and cloning fresh..."
            cd ..
            rm -rf "$CLONE_DIR"
        else
            # Stash any local changes to avoid conflicts
            if git diff --quiet && git diff --staged --quiet; then
                log "No local changes detected"
            else
                log_warning "Local changes detected. Stashing them..."
                if ! git stash push -m "Auto-stashed by deployment script $(date +'%Y-%m-%d %H:%M:%S')"; then
                    log_error "Failed to stash local changes"
                    exit 1
                fi
                log_success "Local changes stashed successfully"
            fi
            
            # Fetch and pull latest changes
            log "Fetching latest changes from remote..."
            if ! git fetch origin; then
                log_error "Failed to fetch from remote repository"
                exit 1
            fi
            
            log "Pulling latest changes..."
            if ! git pull origin "$BRANCH_NAME"; then
                log_error "Failed to pull changes from branch $BRANCH_NAME"
                exit 1
            fi
            
            log_success "Repository updated successfully"
            # Set REPO_DIR after successful pull
            REPO_DIR="$CLONE_DIR"
            export REPO_DIR
            cd ..
            return 0
        fi
    fi
    
    # Clone the repository (if we get here, either directory didn't exist or was removed)
    log "Cloning repository from: $GIT_REPO_URL"
    
    if [[ "$GIT_REPO_URL" =~ ^https:// ]]; then
        # Use authenticated URL with PAT for HTTPS
        if ! git clone "$AUTH_GIT_URL" "$CLONE_DIR"; then
            log_error "Failed to clone repository"
            # Clean up on failure
            if [ -d "$CLONE_DIR" ]; then
                rm -rf "$CLONE_DIR"
            fi
            exit 1
        fi
    else
        # Use original URL for SSH
        if ! git clone "$GIT_REPO_URL" "$CLONE_DIR"; then
            log_error "Failed to clone repository via SSH"
            if [ -d "$CLONE_DIR" ]; then
                rm -rf "$CLONE_DIR"
            fi
            exit 1
        fi
    fi
    
    log_success "Repository cloned successfully"
    
    # Switch to specified branch
    cd "$CLONE_DIR"
    
    # Check if branch exists
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        log "Switching to existing branch: $BRANCH_NAME"
        if ! git checkout "$BRANCH_NAME"; then
            log_error "Failed to switch to branch $BRANCH_NAME"
            exit 1
        fi
    else
        # Check if branch exists remotely
        if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
            log "Branch exists remotely. Creating local tracking branch: $BRANCH_NAME"
            if ! git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME"; then
                log_error "Failed to create tracking branch for $BRANCH_NAME"
                exit 1
            fi
        else
            log_error "Branch $BRANCH_NAME does not exist locally or remotely"
            log "Available branches:"
            git branch -r
            exit 1
        fi
    fi
    
    log_success "Switched to branch: $BRANCH_NAME"
    
    # Get the latest commit info
    LATEST_COMMIT=$(git log -1 --oneline)
    log "Latest commit: $LATEST_COMMIT"
    
    # Set and export REPO_DIR before going back
    REPO_DIR="$CLONE_DIR"
    export REPO_DIR
    
    cd ..
    
    log_success "Section 2 completed successfully"
}

# Section 3: Navigate and Verify Docker Files
navigate_and_verify_docker() {
    log "Starting Section 3: Navigate and Verify Docker Files"
    echo "=========================================="
    echo "  Section 3: Navigate and Verify Docker Files"
    echo "=========================================="
    
    # Debug: Check what variables are set
    log "Debug: Current directory: $(pwd)"
    log "Debug: REPO_DIR value: ${REPO_DIR:-NOT SET}"
    log "Debug: CLONE_DIR value: ${CLONE_DIR:-NOT SET}"
    
    # Check if REPO_DIR is set, if not try to derive it
    if [ -z "$REPO_DIR" ]; then
        log_warning "REPO_DIR not set, attempting to derive from Git URL..."
        REPO_NAME=$(basename "$GIT_REPO_URL" .git)
        DERIVED_REPO_DIR="$PWD/$REPO_NAME"
        
        if [ -d "$DERIVED_REPO_DIR" ]; then
            REPO_DIR="$DERIVED_REPO_DIR"
            log "Derived REPO_DIR: $REPO_DIR"
        else
            log_error "Cannot determine repository directory."
            log "Please ensure the repository was cloned successfully in Section 2."
            exit 1
        fi
    fi
    
    # Navigate into the cloned directory
    log "Navigating to repository directory: $REPO_DIR"
    if ! cd "$REPO_DIR"; then
        log_error "Failed to navigate to repository directory: $REPO_DIR"
        log "Current directory: $(pwd)"
        log "Directory contents:"
        ls -la
        exit 1
    fi
    
    log_success "Successfully navigated to: $(pwd)"
    
    # Verify Docker configuration files exist
    log "Checking for Docker configuration files..."
    
    DOCKER_FILES_FOUND=()
    DOCKER_CONFIGS=(
        "Dockerfile"
        "docker-compose.yml"
        "docker-compose.yaml"
        "docker-compose.prod.yml"
        "docker-compose.production.yml"
        "compose.yml"
        "compose.yaml"
    )
    
    for docker_file in "${DOCKER_CONFIGS[@]}"; do
        if [ -f "$docker_file" ]; then
            DOCKER_FILES_FOUND+=("$docker_file")
            log "Found: $docker_file"
        fi
    done
    
    # Check if we found any Docker files
    if [ ${#DOCKER_FILES_FOUND[@]} -eq 0 ]; then
        log_error "No Docker configuration files found in the repository!"
        log "Expected one of: Dockerfile, docker-compose.yml, compose.yml, etc."
        log "Current directory contents:"
        ls -la
        exit 1
    fi
    
    log_success "Found ${#DOCKER_FILES_FOUND[@]} Docker configuration file(s): ${DOCKER_FILES_FOUND[*]}"
    
    # Additional validation for key files
    if [ -f "Dockerfile" ]; then
        log "Validating Dockerfile..."
        if [ ! -s "Dockerfile" ]; then
            log_error "Dockerfile exists but is empty"
            exit 1
        fi
        
        # Basic syntax check - look for FROM instruction
        if ! grep -q "^FROM " Dockerfile; then
            log_warning "Dockerfile does not appear to contain a FROM instruction"
        else
            BASE_IMAGE=$(grep "^FROM " Dockerfile | head -1 | cut -d' ' -f2)
            log "Dockerfile uses base image: $BASE_IMAGE"
        fi
        
        log_success "Dockerfile validation passed"
    fi
    
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] || [ -f "compose.yaml" ]; then
        log "Validating docker-compose file..."
        
        # Determine which compose file to check
        COMPOSE_FILE=""
        for file in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
            if [ -f "$file" ]; then
                COMPOSE_FILE="$file"
                break
            fi
        done
        
        if [ -n "$COMPOSE_FILE" ]; then
            if [ ! -s "$COMPOSE_FILE" ]; then
                log_error "$COMPOSE_FILE exists but is empty"
                exit 1
            fi
            
            # Basic YAML syntax check
            if command -v docker-compose &> /dev/null || command -v docker &> /dev/null; then
                if command -v docker &> /dev/null; then
                    if docker compose -f "$COMPOSE_FILE" config --quiet &>/dev/null; then
                        log_success "docker-compose file syntax is valid"
                    else
                        log_warning "docker-compose file may have syntax issues"
                    fi
                elif command -v docker-compose &> /dev/null; then
                    if docker-compose -f "$COMPOSE_FILE" config --quiet &>/dev/null; then
                        log_success "docker-compose file syntax is valid"
                    else
                        log_warning "docker-compose file may have syntax issues"
                    fi
                fi
            else
                log_warning "Docker not available for compose file validation"
            fi
        fi
    fi
    
    # Display project structure for context
    log "Project structure overview:"
    find . -maxdepth 2 -type f -name "*.yml" -o -name "*.yaml" -o -name "Dockerfile" -o -name "*.env*" | head -10 | while read -r file; do
        log "  - $file"
    done
    
    # Count total files found for context
    FILE_COUNT=$(find . -maxdepth 2 -type f -name "*.yml" -o -name "*.yaml" -o -name "Dockerfile" -o -name "*.env*" | wc -l)
    if [ "$FILE_COUNT" -gt 10 ]; then
        log "  ... and $((FILE_COUNT - 10)) more configuration files"
    fi
    
    log_success "Section 3 completed successfully"
    log "Current working directory: $(pwd)"
}

# Section 4: SSH into Remote Server (Connectivity Only)
ssh_remote_server() {
    log "Starting Section 4: SSH into Remote Server"
    echo "=========================================="
    echo "  Section 4: SSH into Remote Server"
    echo "=========================================="
    
    # Build SSH base command for future use
    SSH_BASE_CMD="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
    REMOTE_SSH_CMD="$SSH_BASE_CMD $SSH_USERNAME@$SERVER_IP"
    export REMOTE_SSH_CMD
    
    # Test 1: Basic connectivity check (ping) - skip if ping is not available
    log "Testing basic network connectivity to $SERVER_IP..."
    if command -v ping &> /dev/null; then
        if ping -c 2 -W 2 "$SERVER_IP" &>/dev/null; then
            log_success "Network connectivity test passed"
        else
            log_warning "Ping test failed (this might be normal if ICMP is blocked)"
        fi
    else
        log_warning "Ping command not available, skipping network test"
    fi
    
    # Test 2: Simple SSH connection test
    log "Testing SSH connection to $SSH_USERNAME@$SERVER_IP..."
    
    # Use a simple echo command to test SSH
    if eval "$REMOTE_SSH_CMD" "echo 'SSH connection successful'"; then
        log_success "SSH connection test passed"
    else
        log_error "SSH connection test failed"
        log "Please check:"
        log "  - SSH key permissions: chmod 600 $SSH_KEY_PATH"
        log "  - SSH key is added to authorized_keys on server"
        log "  - Server is accessible on port 22"
        log "  - Username and IP are correct"
        exit 1
    fi
    
    # Set up remote deployment directory path for future use
    REMOTE_DEPLOY_DIR="/home/$SSH_USERNAME/deployments/$(basename "$GIT_REPO_URL" .git)"
    export REMOTE_DEPLOY_DIR
    
    log_success "Section 4 completed successfully"
    log "SSH connection established and verified"
    log "Ready for remote environment setup in Section 5"
}

# # Section 5: Prepare Remote Environment
# prepare_remote_environment() {
#     log "Starting Section 5: Prepare Remote Environment"
#     echo "=========================================="
#     echo "  Section 5: Prepare Remote Environment"
#     echo "=========================================="
    
#     log "Preparing remote server environment on $SERVER_IP..."
    
#     # Use NON-INTERACTIVE SSH command (NO -t flag)
#     REMOTE_SSH_CMD="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR $SSH_USERNAME@$SERVER_IP"
    
#     # 1. Update system packages (without upgrade)
#     log "Updating package lists on remote server..."
#     if eval "$REMOTE_SSH_CMD" "sudo apt-get update -qq"; then
#         log_success "Package lists updated successfully"
#     else
#         log_error "Failed to update package lists"
#         exit 1
#     fi
    
#     # 2. Install Docker if not present - IMPROVED DETECTION
#     log "Checking Docker installation..."
    
#     # Test if Docker command actually works (not just exists)
#     DOCKER_CHECK=$(eval "$REMOTE_SSH_CMD" "docker --version 2>/dev/null && echo 'DOCKER_WORKS' || echo 'DOCKER_MISSING'")
    
#     if [[ "$DOCKER_CHECK" == *"DOCKER_WORKS"* ]]; then
#         DOCKER_VERSION=$(eval "$REMOTE_SSH_CMD" "docker --version 2>/dev/null" | head -1)
#         log_success "Docker is already installed and working: $DOCKER_VERSION"
#     else
#         log "Docker not found or not working. Installing Docker..."
        
#         # Install Docker using official script - with auto-accept and no prompts
# if eval "$REMOTE_SSH_CMD" 'bash -s' <<'EOF'
#     set -e
#     export DEBIAN_FRONTEND=noninteractive
#     curl -fsSL https://get.docker.com -o get-docker.sh
#     sudo sh get-docker.sh
#     rm -f get-docker.sh
# EOF
# then

#             log_success "Docker installed successfully"
            
#             # Start Docker service
#             eval "$REMOTE_SSH_CMD" "sudo systemctl start docker && sudo systemctl enable docker"
#         else
#             log_error "Failed to install Docker"
#             exit 1
#         fi
#     fi
    
#     # 3. Install Docker Compose if not present
#     # log "Checking Docker Compose installation..."
#     # COMPOSE_CHECK=$(eval "$REMOTE_SSH_CMD" "(docker-compose --version || docker compose version) 2>/dev/null && echo 'COMPOSE_WORKS' || echo 'COMPOSE_MISSING'")
    
#     # if [[ "$COMPOSE_CHECK" == *"COMPOSE_WORKS"* ]]; then
#     #     log_success "Docker Compose is already installed"
#     # else
#     #     log "Docker Compose not found. Installing Docker Compose..."
        
#     #     if eval "$REMOTE_SSH_CMD" "
#     #         sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
#     #         sudo chmod +x /usr/local/bin/docker-compose
#     #     "; then
#     #         log_success "Docker Compose installed successfully"
#     #     else
#     #         log_error "Failed to install Docker Compose"
#     #         exit 1
#     #     fi
#     # fi
#     log "Checking Docker Compose installation..."

# COMPOSE_CHECK=$(ssh -i "$SSH_KEY_PATH" \
#     -o StrictHostKeyChecking=no \
#     -o ConnectTimeout=10 \
#     -o BatchMode=yes \
#     -o LogLevel=ERROR \
#     "$SSH_USERNAME@$SERVER_IP" \
#     "docker-compose --version 2>/dev/null || docker compose version 2>/dev/null && echo COMPOSE_WORKS || echo COMPOSE_MISSING")

# if [[ "$COMPOSE_CHECK" == *"COMPOSE_WORKS"* ]]; then
#     log_success "Docker Compose is already installed"
# else
#     log "Docker Compose not found. Installing Docker Compose..."

#     if ssh -i "$SSH_KEY_PATH" \
#         -o StrictHostKeyChecking=no \
#         -o ConnectTimeout=10 \
#         -o BatchMode=yes \
#         -o LogLevel=ERROR \
#         "$SSH_USERNAME@$SERVER_IP" \
#         "sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose"; then
#         log_success "Docker Compose installed successfully"
#     else
#         log_error "Failed to install Docker Compose"
#         exit 1
#     fi
# fi

# # 4. Install Nginx if not present
# log "Checking Nginx installation..."

# NGINX_CHECK=$(ssh -i "$SSH_KEY_PATH" \
#     -o StrictHostKeyChecking=no \
#     -o ConnectTimeout=10 \
#     -o BatchMode=yes \
#     -o LogLevel=ERROR \
#     -n \
#     "$SSH_USERNAME@$SERVER_IP" \
#     "nginx -v 2>&1 && echo NGINX_WORKS || echo NGINX_MISSING")

# if [[ "$NGINX_CHECK" == *"NGINX_WORKS"* ]]; then
#     log_success "Nginx is already installed"
# else
#     log "Nginx not found. Installing Nginx..."

#     if ssh -i "$SSH_KEY_PATH" \
#         -o StrictHostKeyChecking=no \
#         -o ConnectTimeout=10 \
#         -o BatchMode=yes \
#         -o LogLevel=ERROR \
#         -n \
#         "$SSH_USERNAME@$SERVER_IP" \
#         "export DEBIAN_FRONTEND=noninteractive; sudo apt-get update -qq && sudo apt-get install -y -qq nginx"; then
#         log_success "Nginx installed successfully"
#     else
#         log_error "Failed to install Nginx"
#         exit 1
#     fi
# fi

    
#     # 5. Enable and start services
#     log "Enabling and starting services..."
    
#     # Enable Docker service
#     if eval "$REMOTE_SSH_CMD" "sudo systemctl enable docker && sudo systemctl start docker"; then
#         log_success "Docker service enabled and started"
#     else
#         log_error "Failed to enable/start Docker service"
#         exit 1
#     fi
    
#     # Enable Nginx service
#     if eval "$REMOTE_SSH_CMD" "sudo systemctl enable nginx && sudo systemctl start nginx"; then
#         log_success "Nginx service enabled and started"
#     else
#         log_error "Failed to enable/start Nginx service"
#         exit 1
#     fi
    
#     # 6. Confirm installation versions
#     log "Confirming installation versions..."
    
#     DOCKER_VERSION=$(eval "$REMOTE_SSH_CMD" "docker --version 2>/dev/null" | head -1)
#     DOCKER_COMPOSE_VERSION=$(eval "$REMOTE_SSH_CMD" "docker-compose --version 2>/dev/null || docker compose version --short 2>/dev/null")
#     NGINX_VERSION=$(eval "$REMOTE_SSH_CMD" "nginx -v 2>&1 | head -1")
    
#     log_success "Installation versions confirmed:"
#     log "  Docker: $DOCKER_VERSION"
#     log "  Docker Compose: $DOCKER_COMPOSE_VERSION"
#     log "  Nginx: $NGINX_VERSION"
    
#     # 7. Create deployment directory
#     log "Creating deployment directory: $REMOTE_DEPLOY_DIR"
#     if eval "$REMOTE_SSH_CMD" "mkdir -p \"$REMOTE_DEPLOY_DIR\""; then
#         log_success "Deployment directory created successfully"
#     else
#         log_error "Failed to create deployment directory"
#         exit 1
#     fi
    
#     log_success "Section 5 completed successfully"
#     log "Remote environment is ready for deployment"
# }

# Section 5: Prepare Remote Environment
prepare_remote_environment() {
    log "Starting Section 5: Prepare Remote Environment"
    echo "=========================================="
    echo "  Section 5: Prepare Remote Environment"
    echo "=========================================="
    
    log "Preparing remote server environment on $SERVER_IP..."
    
    # Use NON-INTERACTIVE SSH command (NO -t flag)
    REMOTE_SSH_CMD="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR $SSH_USERNAME@$SERVER_IP"
    
    # 1. Update system packages (without upgrade)
    log "Updating package lists on remote server..."
    if eval "$REMOTE_SSH_CMD" "sudo apt-get update -qq"; then
        log_success "Package lists updated successfully"
    else
        log_error "Failed to update package lists"
        exit 1
    fi
    
    # 2. Install Docker if not present - IMPROVED DETECTION
    log "Checking Docker installation..."
    
    # Test if Docker command actually works (not just exists)
    DOCKER_CHECK=$(eval "$REMOTE_SSH_CMD" "docker --version 2>/dev/null && echo 'DOCKER_WORKS' || echo 'DOCKER_MISSING'")
    
    if [[ "$DOCKER_CHECK" == *"DOCKER_WORKS"* ]]; then
        DOCKER_VERSION=$(eval "$REMOTE_SSH_CMD" "docker --version 2>/dev/null" | head -1)
        log_success "Docker is already installed and working: $DOCKER_VERSION"
    else
        log "Docker not found or not working. Installing Docker..."
        
        # Install Docker using official script - with auto-accept and no prompts
        if eval "$REMOTE_SSH_CMD" 'bash -s' <<'EOF'
    set -e
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm -f get-docker.sh
EOF
        then
            log_success "Docker installed successfully"
            
            # Start Docker service
            eval "$REMOTE_SSH_CMD" "sudo systemctl start docker && sudo systemctl enable docker"
        else
            log_error "Failed to install Docker"
            exit 1
        fi
    fi
    
    # 3. Install Docker Compose if not present
    log "Checking Docker Compose installation..."

    COMPOSE_CHECK=$(ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        "$SSH_USERNAME@$SERVER_IP" \
        "docker-compose --version 2>/dev/null || docker compose version 2>/dev/null && echo COMPOSE_WORKS || echo COMPOSE_MISSING")

    if [[ "$COMPOSE_CHECK" == *"COMPOSE_WORKS"* ]]; then
        log_success "Docker Compose is already installed"
    else
        log "Docker Compose not found. Installing Docker Compose..."

        if ssh -i "$SSH_KEY_PATH" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            -o BatchMode=yes \
            -o LogLevel=ERROR \
            "$SSH_USERNAME@$SERVER_IP" \
            "sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose"; then
            log_success "Docker Compose installed successfully"
        else
            log_error "Failed to install Docker Compose"
            exit 1
        fi
    fi

    # 4. Install Nginx if not present - FIXED VERSION
    log "Checking Nginx installation..."

    NGINX_CHECK=$(ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        -o LogLevel=ERROR \
        -n \
        "$SSH_USERNAME@$SERVER_IP" \
        "which nginx && echo NGINX_WORKS || echo NGINX_MISSING")

    if [[ "$NGINX_CHECK" == *"NGINX_WORKS"* ]]; then
        log_success "Nginx is already installed"
    else
        log "Nginx not found. Installing Nginx..."

        # Install Nginx with proper error handling
        if ssh -i "$SSH_KEY_PATH" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            -o BatchMode=yes \
            -o LogLevel=ERROR \
            -n \
            "$SSH_USERNAME@$SERVER_IP" \
            "export DEBIAN_FRONTEND=noninteractive && sudo apt-get install -y nginx"; then
            
            # Verify Nginx was actually installed
            NGINX_VERIFY=$(ssh -i "$SSH_KEY_PATH" \
                -o StrictHostKeyChecking=no \
                -o ConnectTimeout=10 \
                -o BatchMode=yes \
                -o LogLevel=ERROR \
                -n \
                "$SSH_USERNAME@$SERVER_IP" \
                "which nginx && echo 'INSTALLED' || echo 'FAILED'")
            
            if [[ "$NGINX_VERIFY" == *"INSTALLED"* ]]; then
                log_success "Nginx installed successfully"
            else
                log_error "Nginx installation completed but nginx command not found"
                exit 1
            fi
        else
            log_error "Failed to install Nginx"
            exit 1
        fi
    fi
    
    # 5. Enable and start services - FIXED NGINX SERVICE HANDLING
    log "Enabling and starting services..."
    
    # Enable Docker service
    if eval "$REMOTE_SSH_CMD" "sudo systemctl enable docker && sudo systemctl start docker"; then
        log_success "Docker service enabled and started"
    else
        log_error "Failed to enable/start Docker service"
        exit 1
    fi
    
    # Enable Nginx service - with better error handling
    log "Setting up Nginx service..."
    NGINX_SERVICE_CHECK=$(eval "$REMOTE_SSH_CMD" "systemctl list-unit-files | grep -q nginx.service && echo 'EXISTS' || echo 'MISSING'")
    
    if [[ "$NGINX_SERVICE_CHECK" == *"EXISTS"* ]]; then
        if eval "$REMOTE_SSH_CMD" "sudo systemctl enable nginx && sudo systemctl start nginx"; then
            log_success "Nginx service enabled and started"
        else
            log_warning "Nginx service exists but failed to start. Checking status..."
            # Check what's wrong with nginx
            eval "$REMOTE_SSH_CMD" "sudo systemctl status nginx --no-pager || nginx -t || echo 'Nginx configuration check failed'"
            log_warning "Continuing deployment despite Nginx service issues"
        fi
    else
        log_warning "Nginx service unit not found. Nginx may be installed but service not configured."
        log "Attempting to start nginx directly..."
        if eval "$REMOTE_SSH_CMD" "sudo nginx -t && sudo nginx"; then
            log_success "Nginx started directly (without systemd service)"
        else
            log_warning "Nginx failed to start. Continuing deployment without Nginx for now."
        fi
    fi
    
    # 6. Confirm installation versions
    log "Confirming installation versions..."
    
    DOCKER_VERSION=$(eval "$REMOTE_SSH_CMD" "docker --version 2>/dev/null" | head -1)
    DOCKER_COMPOSE_VERSION=$(eval "$REMOTE_SSH_CMD" "docker-compose --version 2>/dev/null || docker compose version --short 2>/dev/null")
    NGINX_VERSION=$(eval "$REMOTE_SSH_CMD" "nginx -v 2>&1 | head -1")
    
    log_success "Installation versions confirmed:"
    log "  Docker: $DOCKER_VERSION"
    log "  Docker Compose: $DOCKER_COMPOSE_VERSION"
    log "  Nginx: $NGINX_VERSION"
    
    # 7. Create deployment directory
    log "Creating deployment directory: $REMOTE_DEPLOY_DIR"
    if eval "$REMOTE_SSH_CMD" "mkdir -p \"$REMOTE_DEPLOY_DIR\""; then
        log_success "Deployment directory created successfully"
    else
        log_error "Failed to create deployment directory"
        exit 1
    fi
    
    log_success "Section 5 completed successfully"
    log "Remote environment is ready for deployment"
}

# Function to execute remote commands
execute_remote() {
    local command="$1"
    local description="${2:-Executing remote command}"
    
    log "$description..."
    log "Remote command: $command"
    
    if eval "$REMOTE_SSH_CMD" "\"$command\""; then
        log_success "Remote command executed successfully"
        return 0
    else
        log_error "Remote command failed: $command"
        return 1
    fi
}

# Main execution
main() {
    log "Starting deployment script"
    
    # Check if running interactively
    if [ ! -t 0 ]; then
        log_error "Script must be run interactively to collect parameters"
        exit 1
    fi
    
    # Section 1: Parameter Collection
    collect_parameters
    export_parameters
    
    # Section 2: Repository Cloning
    clone_repository
    
    # Section 3: Navigate and Verify Docker Files
    navigate_and_verify_docker
    
    # Section 4: SSH into Remote Server
    ssh_remote_server
    
    # Section 5: Prepare Remote Environment
    prepare_remote_environment
    
    log_success "Sections 1-5 completed successfully"
    
    # Display next steps
    echo
    log "Next steps:"
    log "1. Transfer application files to remote server"
    log "2. Build Docker images on remote server"
    log "3. Deploy application using docker-compose"
    log "4. Start containers and verify deployment"
    echo
    
    log "Remote server is fully prepared and ready for deployment"
    log "Deployment directory: $REMOTE_DEPLOY_DIR"
    log "Application port: $APP_PORT"
}

# Run main function
main "$@"