#!/bin/bash

# deploy.sh - Dockerized Application Deployment Script
# Section 1: Parameter Collection and Validation

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

# Main parameter collection function
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
    echo
    read -p "Are these parameters correct? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warning "Parameter collection cancelled by user"
        exit 1
    fi
    
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

# Main execution
main() {
    log "Starting deployment script - Section 1"
    
    # Check if running interactively
    if [ ! -t 0 ]; then
        log_error "Script must be run interactively to collect parameters"
        exit 1
    fi
    
    collect_parameters
    export_parameters
    
    log_success "Section 1 completed successfully. Parameters are ready for deployment."
    
    # Display next steps
    echo
    log "Next steps:"
    log "1. SSH connection test to remote server"
    log "2. Clone and build application"
    log "3. Deploy Docker containers"
    echo
}

# Run main function
main "$@"