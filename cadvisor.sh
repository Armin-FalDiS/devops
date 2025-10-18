#!/bin/bash

# Docker Metrics Enabler Script for Linux
# Based on: https://docs.docker.com/engine/daemon/prometheus/
# This script configures Docker daemon to expose metrics for external Grafana

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CADVISOR_PORT=8080
CADVISOR_CONTAINER_NAME="cadvisor"

# Grafana configuration variables
GRAFANA_URL=""
GRAFANA_USERNAME=""
GRAFANA_PASSWORD=""
GRAFANA_API_KEY=""

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

# Function to check if Docker is running
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "Docker is running"
}

# Function to get available network interfaces
get_network_interfaces() {
    print_status "Detecting available network interfaces..."
    echo
    
    # Get all network interfaces with their IPs
    local interfaces=()
    local interface_count=0
    
    # Add localhost option
    echo "1) localhost (127.0.0.1) - Local access only"
    interfaces+=("127.0.0.1")
    interface_count=1
    
    # Add all interfaces option
    echo "2) all interfaces (0.0.0.0) - External access"
    interfaces+=("0.0.0.0")
    interface_count=2
    
    # Get specific network interfaces
    local iface_num=3
    local current_iface=""
    
    # Try ip addr show first (modern systems)
    if command -v ip >/dev/null 2>&1; then
        # Use a more direct approach with ip command
        local ip_output=$(ip addr show | grep -E "inet [0-9]" | grep -v "127.0.0.1" | grep -v "::1")
        
        while IFS= read -r line; do
            # Extract IP from the line
            local ip=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
            # Get the interface name by looking at the context
            local iface_line=$(ip addr show | grep -B1 "$ip" | head -1)
            local iface=$(echo "$iface_line" | awk '{print $2}' | sed 's/://')
            
            if [[ -n "$ip" && -n "$iface" ]]; then
                echo "$iface_num) $iface ($ip)"
                interfaces+=("$ip")
                ((iface_num++))
            fi
        done <<< "$ip_output"
    # Fallback to ifconfig if ip command is not available
    elif command -v ifconfig >/dev/null 2>&1; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[a-zA-Z0-9]+: ]]; then
                current_iface=$(echo "$line" | awk '{print $1}' | sed 's/://')
            elif [[ "$line" =~ inet[[:space:]]+[0-9] ]]; then
                local ip=$(echo "$line" | awk '{print $2}')
                if [[ -n "$ip" && "$ip" != "127.0.0.1" && "$ip" != "::1" && -n "$current_iface" ]]; then
                    echo "$iface_num) $current_iface ($ip)"
                    interfaces+=("$ip")
                    ((iface_num++))
                fi
            fi
        done < <(ifconfig)
    else
        print_warning "Neither 'ip' nor 'ifconfig' command found. Only showing localhost and all interfaces options."
    fi
    
    # Show summary of detected interfaces
    if [[ ${#interfaces[@]} -gt 2 ]]; then
        print_success "Found ${#interfaces[@]} network interfaces"
    else
        print_warning "Only basic interface options available (localhost and all interfaces)"
    fi
    
    echo
    read -p "Choose interface to bind metrics to (1-$iface_num): " choice
    
    # Validate choice
    if [[ "$choice" -ge 1 && "$choice" -le "$iface_num" ]]; then
        local selected_ip="${interfaces[$((choice-1))]}"
        echo "$selected_ip"
    else
        print_error "Invalid choice. Using localhost for security."
        echo "127.0.0.1"
    fi
}

# Function to deploy cAdvisor container
deploy_cadvisor() {
    print_status "Deploying cAdvisor for detailed container monitoring..."
    
    # Let user choose interface
    local selected_ip=$(get_network_interfaces)
    
    print_status "Selected interface: $selected_ip"
    
    # Stop and remove existing cAdvisor container if it exists
    docker stop "$CADVISOR_CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CADVISOR_CONTAINER_NAME" 2>/dev/null || true
    
    # Deploy cAdvisor container
    docker run -d \
        --name "$CADVISOR_CONTAINER_NAME" \
        --restart unless-stopped \
        --privileged \
        --device /dev/kmsg \
        -p "$selected_ip:$CADVISOR_PORT:8080" \
        -v /:/rootfs:ro \
        -v /var/run:/var/run:ro \
        -v /sys:/sys:ro \
        -v /var/lib/docker/:/var/lib/docker:ro \
        -v /dev/disk/:/dev/disk:ro \
        gcr.io/cadvisor/cadvisor:latest
    
    print_success "cAdvisor deployed successfully"
    print_warning "cAdvisor metrics are now available at: http://$selected_ip:$CADVISOR_PORT/metrics"
    print_warning "cAdvisor web UI is available at: http://$selected_ip:$CADVISOR_PORT"
}

# Function to display connection information
display_connection_info() {
    print_success "cAdvisor container monitoring setup completed!"
    echo
    
    # Get the cAdvisor container's bound address
    local container_port=$(docker port "$CADVISOR_CONTAINER_NAME" 8080 2>/dev/null | cut -d':' -f2 | head -1)
    local container_ip=$(docker port "$CADVISOR_CONTAINER_NAME" 8080 2>/dev/null | cut -d':' -f1 | head -1)
    
    if [[ -z "$container_port" ]]; then
        container_port="$CADVISOR_PORT"
        container_ip="localhost"
    fi
    
    print_status "Connection Information:"
    echo "  📊 Metrics Endpoint: http://$container_ip:$container_port/metrics"
    echo "  🌐 cAdvisor Web UI: http://$container_ip:$container_port"
    echo "  🔍 Local Access: http://localhost:$container_port"
    echo
    
    if [[ -n "$GRAFANA_URL" ]]; then
        print_status "Grafana Data Source Configuration:"
        echo "  URL: http://$container_ip:$container_port"
        echo "  Type: Prometheus"
        echo "  Access: Server (default)"
    else
        print_status "For external Grafana access:"
        echo "  Use the metrics endpoint URL above in your Grafana datasource"
    fi
    echo
    print_status "Available Metrics:"
    echo "  - Per-container CPU usage (container_cpu_usage_seconds_total)"
    echo "  - Per-container memory usage (container_memory_usage_bytes)"
    echo "  - Per-container network I/O (container_network_*_bytes_total)"
    echo "  - Per-container filesystem usage (container_fs_*)"
    echo "  - Container state and lifecycle events"
    echo "  - Resource usage history and trends"
    echo
    print_warning "Note: cAdvisor automatically discovers and monitors all containers."
    print_warning "The web UI provides real-time visualization of container metrics."
}

# Function to test metrics endpoint
test_metrics() {
    print_status "Testing cAdvisor metrics endpoint..."
    
    # Wait a moment for cAdvisor to fully start
    sleep 5
    
    # Get the container's bound port
    local container_port=$(docker port "$CADVISOR_CONTAINER_NAME" 8080 2>/dev/null | cut -d':' -f2 | head -1)
    if [[ -z "$container_port" ]]; then
        container_port="$CADVISOR_PORT"
    fi
    
    if curl -s "http://localhost:$container_port/metrics" > /dev/null 2>&1; then
        print_success "cAdvisor metrics endpoint is accessible at http://localhost:$container_port/metrics"
    else
        print_warning "cAdvisor metrics endpoint not yet accessible. Container may still be starting up."
        print_warning "You can test manually with: curl http://localhost:$container_port/metrics"
        print_warning "Check container status with: docker logs $CADVISOR_CONTAINER_NAME"
    fi
}

# Function to get Grafana credentials from user
get_grafana_credentials() {
    print_status "Grafana Configuration (Optional)"
    echo
    
    read -p "Enter your Grafana URL (or press Enter to skip): " GRAFANA_URL
    
    if [[ -z "$GRAFANA_URL" ]]; then
        print_warning "Skipping Grafana configuration. Docker metrics will still be configured."
        return 1
    fi
    
    echo "Choose authentication method:"
    echo "1) Username/Password"
    echo "2) API Key"
    read -p "Enter choice (1 or 2): " auth_choice
    
    case $auth_choice in
        1)
            read -p "Enter Grafana username: " GRAFANA_USERNAME
            read -s -p "Enter Grafana password: " GRAFANA_PASSWORD
            echo
            ;;
        2)
            read -s -p "Enter Grafana API Key: " GRAFANA_API_KEY
            echo
            ;;
        *)
            print_error "Invalid choice. Skipping Grafana configuration."
            return 1
            ;;
    esac
    
    print_success "Grafana credentials configured"
    return 0
}

# Function to test Grafana connection
test_grafana_connection() {
    print_status "Testing Grafana connection..."
    
    local auth_header=""
    if [[ -n "$GRAFANA_API_KEY" ]]; then
        auth_header="Authorization: Bearer $GRAFANA_API_KEY"
    else
        auth_header="Authorization: Basic $(echo -n "$GRAFANA_USERNAME:$GRAFANA_PASSWORD" | base64)"
    fi
    
    if curl -s -H "$auth_header" "$GRAFANA_URL/api/org" > /dev/null 2>&1; then
        print_success "Grafana connection successful"
        return 0
    else
        print_warning "Failed to connect to Grafana. Skipping Grafana configuration."
        print_warning "Docker metrics will still be configured and available."
        return 1
    fi
}

# Function to create Prometheus datasource in Grafana
create_grafana_datasource() {
    print_status "Creating Prometheus datasource in Grafana..."
    
    local auth_header=""
    if [[ -n "$GRAFANA_API_KEY" ]]; then
        auth_header="Authorization: Bearer $GRAFANA_API_KEY"
    else
        auth_header="Authorization: Basic $(echo -n "$GRAFANA_USERNAME:$GRAFANA_PASSWORD" | base64)"
    fi
    
    # Get the cAdvisor container's bound IP
    local server_ip=$(docker port "$CADVISOR_CONTAINER_NAME" 8080 2>/dev/null | cut -d':' -f1 | head -1)
    if [[ -z "$server_ip" || "$server_ip" == "0.0.0.0" ]]; then
        # If bound to all interfaces, get the actual server IP
        server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    fi
    
    # Create datasource JSON
    local datasource_json=$(cat <<EOF
{
  "name": "cAdvisor",
  "type": "prometheus",
  "url": "http://$server_ip:$CADVISOR_PORT",
  "access": "proxy",
  "isDefault": false,
  "editable": true,
  "jsonData": {
    "httpMethod": "POST"
  }
}
EOF
)
    
    # Create the datasource
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "$auth_header" \
        -d "$datasource_json" \
        "$GRAFANA_URL/api/datasources")
    
    if echo "$response" | grep -q '"id"'; then
        print_success "cAdvisor datasource created successfully in Grafana"
        return 0
    else
        print_warning "Failed to create datasource automatically. Response: $response"
        print_status "You can manually add the datasource in Grafana:"
        print_status "  Name: cAdvisor"
        print_status "  Type: Prometheus"
        print_status "  URL: http://$server_ip:$CADVISOR_PORT"
        return 1
    fi
}

# Function to create a basic cAdvisor monitoring dashboard
create_grafana_dashboard() {
    print_status "Creating cAdvisor monitoring dashboard in Grafana..."
    
    local auth_header=""
    if [[ -n "$GRAFANA_API_KEY" ]]; then
        auth_header="Authorization: Bearer $GRAFANA_API_KEY"
    else
        auth_header="Authorization: Basic $(echo -n "$GRAFANA_USERNAME:$GRAFANA_PASSWORD" | base64)"
    fi
    
    # Basic cAdvisor dashboard JSON
    local dashboard_json=$(cat <<'EOF'
{
  "dashboard": {
    "id": null,
    "title": "cAdvisor Container Monitoring",
    "tags": ["cadvisor", "containers", "docker"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Container CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{name!=\"\"}[5m]) * 100",
            "legendFormat": "{{name}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Container Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{name!=\"\"} / 1024 / 1024",
            "legendFormat": "{{name}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "MB"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Container Network I/O",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(container_network_receive_bytes_total{name!=\"\"}[5m])",
            "legendFormat": "{{name}} - RX"
          },
          {
            "expr": "rate(container_network_transmit_bytes_total{name!=\"\"}[5m])",
            "legendFormat": "{{name}} - TX"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "Bps"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
EOF
)
    
    # Create the dashboard
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "$auth_header" \
        -d "$dashboard_json" \
        "$GRAFANA_URL/api/dashboards/db")
    
    if echo "$response" | grep -q '"id"'; then
        print_success "cAdvisor monitoring dashboard created successfully"
        return 0
    else
        print_warning "Failed to create dashboard automatically. Response: $response"
        print_status "You can manually create a dashboard in Grafana using the cAdvisor datasource"
        return 1
    fi
}

# Main execution
main() {
    print_status "cAdvisor Container Monitoring Setup for Linux"
    print_status "This will deploy cAdvisor for detailed container monitoring and optionally configure Grafana"
    echo
    
    # Check prerequisites
    check_docker
    
    # Get Grafana credentials (optional)
    if get_grafana_credentials; then
        # Test Grafana connection
        if test_grafana_connection; then
            # Deploy cAdvisor
            deploy_cadvisor
            
            # Test metrics endpoint
            test_metrics
            
            # Create Grafana datasource
            create_grafana_datasource
            
            # Create Grafana dashboard
            create_grafana_dashboard
        else
            # Deploy cAdvisor even if Grafana fails
            deploy_cadvisor
            test_metrics
        fi
    else
        # Deploy cAdvisor without Grafana
        deploy_cadvisor
        test_metrics
    fi
    
    # Display final information
    display_connection_info
}

# Run main function
main "$@"
