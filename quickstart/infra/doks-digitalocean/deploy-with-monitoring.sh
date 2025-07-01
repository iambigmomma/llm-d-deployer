#!/bin/bash

# LLM-D Deployment Script with Monitoring for DigitalOcean Kubernetes
# Supports multiple GPU configurations and automatic monitoring setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_CONFIGS_DIR="${SCRIPT_DIR}/gpu-configs"
MONITORING_DIR="${SCRIPT_DIR}/monitoring"
QUICKSTART_DIR="${SCRIPT_DIR}/../.."

# Default values
GPU_TYPE=""
INSTALL_MONITORING=true
HUGGINGFACE_TOKEN=""
UNINSTALL=false

# Print colored output
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

# Show usage
show_usage() {
    cat << EOF
🚀 LLM-D Deployment Script for DigitalOcean Kubernetes

Usage: $0 [OPTIONS]

Options:
    -g, --gpu TYPE          GPU type (rtx-4000-ada, rtx-6000-ada, l40s)
    -t, --token TOKEN       HuggingFace token (required)
    -m, --no-monitoring     Skip monitoring installation
    -u, --uninstall         Uninstall LLM-D and monitoring
    -h, --help              Show this help message

GPU Types:
    rtx-4000-ada           NVIDIA RTX 4000 Ada (20GB VRAM)
    rtx-6000-ada           NVIDIA RTX 6000 Ada (48GB VRAM)  
    l40s                   NVIDIA L40S (48GB VRAM)

Examples:
    # Deploy with RTX 4000 Ada
    $0 -g rtx-4000-ada -t hf_xxxxxxxxxx

    # Deploy with L40S, skip monitoring
    $0 -g l40s -t hf_xxxxxxxxxx -m

    # Uninstall everything
    $0 -u

Environment Variables:
    HF_TOKEN               HuggingFace token (alternative to -t)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--gpu)
                GPU_TYPE="$2"
                shift 2
                ;;
            -t|--token)
                HUGGINGFACE_TOKEN="$2"
                shift 2
                ;;
            -m|--no-monitoring)
                INSTALL_MONITORING=false
                shift
                ;;
            -u|--uninstall)
                UNINSTALL=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    if [[ "$UNINSTALL" == "true" ]]; then
        return 0
    fi
    
    # Check HuggingFace token
    if [[ -z "$HUGGINGFACE_TOKEN" && -n "${HF_TOKEN:-}" ]]; then
        HUGGINGFACE_TOKEN="$HF_TOKEN"
    fi
    
    if [[ -z "$HUGGINGFACE_TOKEN" ]]; then
        print_error "HuggingFace token is required. Use -t or set HF_TOKEN environment variable"
        exit 1
    fi
    
    # Check GPU type
    if [[ -z "$GPU_TYPE" ]]; then
        print_error "GPU type is required. Use -g option"
        show_usage
        exit 1
    fi
    
    # Validate GPU type
    case "$GPU_TYPE" in
        rtx-4000-ada|rtx-6000-ada|l40s)
            ;;
        *)
            print_error "Invalid GPU type: $GPU_TYPE"
            print_error "Supported types: rtx-4000-ada, rtx-6000-ada, l40s"
            exit 1
            ;;
    esac
    
    # Check if config file exists
    local config_file="${GPU_CONFIGS_DIR}/${GPU_TYPE}-values.yaml"
    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration file not found: $config_file"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if quickstart directory exists
    if [[ ! -d "$QUICKSTART_DIR" ]]; then
        print_error "Quickstart directory not found: $QUICKSTART_DIR"
        exit 1
    fi
    
    # Check if llmd-installer script exists
    if [[ ! -f "${QUICKSTART_DIR}/llmd-installer.sh" ]]; then
        print_error "llmd-installer.sh not found in: $QUICKSTART_DIR"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Uninstall function
uninstall_everything() {
    print_status "Uninstalling LLM-D and monitoring..."
    
    # Uninstall LLM-D
    print_status "Uninstalling LLM-D..."
    cd "$QUICKSTART_DIR"
    if ./llmd-installer.sh -u; then
        print_success "LLM-D uninstalled successfully"
    else
        print_warning "LLM-D uninstall had some issues"
    fi
    
    # Uninstall monitoring
    print_status "Uninstalling monitoring stack..."
    if kubectl get namespace llm-d-monitoring &> /dev/null; then
        helm uninstall prometheus -n llm-d-monitoring || true
        kubectl delete namespace llm-d-monitoring || true
        print_success "Monitoring stack uninstalled"
    else
        print_warning "Monitoring namespace not found"
    fi
    
    print_success "🎉 Uninstallation completed!"
}

# Install LLM-D
install_llm_d() {
    local config_file="${GPU_CONFIGS_DIR}/${GPU_TYPE}-values.yaml"
    
    print_status "Installing LLM-D with GPU configuration: $GPU_TYPE"
    print_status "Using config file: $config_file"
    
    cd "$QUICKSTART_DIR"
    
    # Export HuggingFace token
    export HF_TOKEN="$HUGGINGFACE_TOKEN"
    
    # Install LLM-D with GPU-specific configuration
    if ./llmd-installer.sh -f "$config_file"; then
        print_success "LLM-D installed successfully"
    else
        print_error "LLM-D installation failed"
        exit 1
    fi
}

# Install monitoring
install_monitoring() {
    print_status "Installing monitoring stack..."
    
    cd "$MONITORING_DIR"
    
    # Make monitoring script executable
    chmod +x setup-monitoring.sh
    
    # Run monitoring setup
    if ./setup-monitoring.sh; then
        print_success "Monitoring stack installed successfully"
    else
        print_error "Monitoring installation failed"
        exit 1
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    print_status "Waiting for LLM-D deployment to be ready..."
    
    # Wait for namespace to exist
    local max_wait=300
    local count=0
    while ! kubectl get namespace llm-d &> /dev/null && [[ $count -lt $max_wait ]]; do
        sleep 2
        ((count+=2))
    done
    
    if [[ $count -ge $max_wait ]]; then
        print_error "Timeout waiting for llm-d namespace"
        return 1
    fi
    
    # Wait for deployments to be ready
    print_status "Waiting for pods to be ready (this may take several minutes)..."
    kubectl wait --for=condition=available deployment --all -n llm-d --timeout=900s
    
    print_success "LLM-D deployment is ready"
}

# Show deployment status
show_deployment_status() {
    echo ""
    echo "=================================="
    echo "🎉 Deployment Status"
    echo "=================================="
    echo ""
    
    # LLM-D status
    print_status "LLM-D Status:"
    kubectl get pods -n llm-d
    echo ""
    
    # Services
    print_status "LLM-D Services:"
    kubectl get svc -n llm-d
    echo ""
    
    if [[ "$INSTALL_MONITORING" == "true" ]]; then
        # Monitoring status
        print_status "Monitoring Status:"
        kubectl get pods -n llm-d-monitoring
        echo ""
        
        # Get Grafana password
        local grafana_password
        grafana_password=$(kubectl get secret prometheus-grafana -n llm-d-monitoring -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo "Unable to retrieve")
        
        echo "📊 Access Information:"
        echo "  Grafana: kubectl port-forward -n llm-d-monitoring svc/prometheus-grafana 3000:80"
        echo "  URL: http://localhost:3000"
        echo "  Username: admin"
        echo "  Password: $grafana_password"
        echo ""
        echo "  Prometheus: kubectl port-forward -n llm-d-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
        echo "  URL: http://localhost:9090"
        echo ""
        echo "💡 To get Grafana password later:"
        echo "  kubectl get secret prometheus-grafana -n llm-d-monitoring -o jsonpath=\"{.data.admin-password}\" | base64 -d"
        echo ""
    fi
    
    echo "🧪 Test Commands:"
    echo "  cd ${QUICKSTART_DIR}"
    echo "  ./test-request.sh"
    echo ""
}

# Main execution
main() {
    echo "🚀 LLM-D Deployment for DigitalOcean Kubernetes"
    echo "==============================================="
    echo ""
    
    parse_args "$@"
    validate_inputs
    check_prerequisites
    
    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_everything
        return 0
    fi
    
    print_status "Deployment Configuration:"
    print_status "  GPU Type: $GPU_TYPE"
    print_status "  Monitoring: $INSTALL_MONITORING"
    print_status "  Config: ${GPU_CONFIGS_DIR}/${GPU_TYPE}-values.yaml"
    echo ""
    
    # Install LLM-D
    install_llm_d
    
    # Wait for deployment
    wait_for_deployment
    
    # Install monitoring if requested
    if [[ "$INSTALL_MONITORING" == "true" ]]; then
        install_monitoring
    fi
    
    # Show status
    show_deployment_status
    
    print_success "🎉 Deployment completed successfully!"
    echo ""
    echo "💡 Next Steps:"
    echo "  1. Test the deployment: cd ${QUICKSTART_DIR} && ./test-request.sh"
    if [[ "$INSTALL_MONITORING" == "true" ]]; then
        echo "  2. Access Grafana: kubectl port-forward -n llm-d-monitoring svc/prometheus-grafana 3000:80"
        echo "  3. Open http://localhost:3000 (admin/prom-operator)"
    fi
    echo ""
}

# Run main function
main "$@" 