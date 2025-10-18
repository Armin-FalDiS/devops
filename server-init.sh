#!/bin/bash

# Server Initialization Script for Deployer Action
# Sets up Docker, nginx, cAdvisor, and deployer user for automated deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Update system and install packages
install_packages() {
    print_status "Updating package lists and installing required packages..."
    
    apt update
    apt install -y docker.io nginx apache2-utils curl wget
    
    print_success "Packages installed successfully"
}

# Setup Docker
setup_docker() {
    print_status "Setting up Docker..."
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    # Verify Docker is running
    if docker info >/dev/null 2>&1; then
        print_success "Docker is running"
    else
        print_error "Docker failed to start"
        exit 1
    fi
}

# Create deployer user
create_deployer_user() {
    print_status "Creating deployer user..."
    
    # Create deployer user with home directory /opt
    useradd -m -d /opt -s /bin/bash deployer 2>/dev/null || print_warning "Deployer user may already exist"
    
    # Set proper permissions on /opt
    chown -R deployer:deployer /opt
    chmod 755 /opt
    
    # Add deployer to docker group
    usermod -aG docker deployer
    
    # Create SSH directory
    mkdir -p /opt/.ssh
    chown deployer:deployer /opt/.ssh
    chmod 700 /opt/.ssh
    
    # Generate SSH key pair
    print_status "Generating SSH key pair for deployer user..."
    sudo -u deployer ssh-keygen -t ed25519 -f /opt/.ssh/id_ed25519 -N "" -C "deployer@$(hostname)"
    
    # Set proper permissions on SSH keys
    chown deployer:deployer /opt/.ssh/id_ed25519*
    chmod 600 /opt/.ssh/id_ed25519
    chmod 644 /opt/.ssh/id_ed25519.pub
    
    print_success "Deployer user created with SSH keys"
}

# Setup nginx configuration
setup_nginx() {
    print_status "Setting up nginx configuration..."
    
    # Copy reverse-proxy.conf
    if [[ -f "nginx/reverse-proxy.conf" ]]; then
        cp nginx/reverse-proxy.conf /etc/nginx/reverse-proxy.conf
        print_success "Copied reverse-proxy.conf"
    else
        print_error "nginx/reverse-proxy.conf not found. Please run this script from the devops directory."
        exit 1
    fi
    
    # Copy default site configuration
    if [[ -f "nginx/default" ]]; then
        cp nginx/default /etc/nginx/sites-available/default
        print_success "Copied default nginx configuration"
    else
        print_error "nginx/default not found. Please run this script from the devops directory."
        exit 1
    fi
    
    # Create symlink in sites-enabled
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    
    # Create symlink in deployer user's home for easy access
    ln -sf /etc/nginx/sites-available/default /opt/nginx
    
    # Create SSL directory structure
    mkdir -p /etc/ssl/private
    chmod 700 /etc/ssl/private
    
    # Test nginx configuration
    if nginx -t; then
        print_success "Nginx configuration is valid"
        systemctl reload nginx
        systemctl enable nginx
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Deploy cAdvisor
deploy_cadvisor() {
    print_status "Deploying cAdvisor for container monitoring..."
    
    # Copy cadvisor.sh if it exists
    if [[ -f "cadvisor.sh" ]]; then
        cp cadvisor.sh /opt/cadvisor.sh
        chmod +x /opt/cadvisor.sh
        
        # Run cadvisor.sh and let it do its thing
        print_status "Running cadvisor.sh script..."
        /opt/cadvisor.sh
        
        print_success "cAdvisor deployment completed"
    else
        print_error "cadvisor.sh not found. Please run this script from the devops directory."
        exit 1
    fi
}

# Display completion information
display_completion() {
    print_success "Server initialization completed successfully!"
    echo
    print_status "Next steps:"
    echo "  1. Update domain names in /etc/nginx/sites-available/default"
    echo "     Replace 'example.com' with your actual domain"
    echo
    echo "  2. For GitHub Actions, add this SSH private key as a secret:"
    echo "     File: /opt/.ssh/id_ed25519"
    echo "     Secret name: SSH_PRIVATE_KEY"
    echo
    echo "  3. Optional: Create htpasswd files for authentication:"
    echo "     - /var/www/internal.htpasswd (for staging/dev)"
    echo "     - /var/www/external.htpasswd (for beta)"
    echo
    print_status "Services running:"
    echo "  - Docker: $(systemctl is-active docker)"
    echo "  - Nginx: $(systemctl is-active nginx)"
    echo "  - cAdvisor: http://localhost:8080"
    echo
    print_warning "Remember to update your domain names in the nginx configuration!"
}

# Main execution
main() {
    print_status "Starting server initialization for deployer-action..."
    echo
    
    check_root
    install_packages
    setup_docker
    create_deployer_user
    setup_nginx
    deploy_cadvisor
    display_completion
}

# Run main function
main "$@"
