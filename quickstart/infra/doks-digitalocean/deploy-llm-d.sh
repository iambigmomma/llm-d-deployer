#!/bin/bash

# llm-d Deployment Script for DigitalOcean Kubernetes
# Focused on llm-d core deployment (monitoring separate)

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
QUICKSTART_DIR="${SCRIPT_DIR}/../.."

# Default values
GPU_TYPE=""
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
🚀 llm-d Core Deployment Script for DigitalOcean Kubernetes

Usage: $0 [OPTIONS]

Options:
    -g, --gpu TYPE          GPU type (rtx-4000-ada, rtx-6000-ada, l40s)
    -t, --token TOKEN       HuggingFace token (required)
    -u, --uninstall         Uninstall llm-d
    -h, --help              Show this help message

GPU Types:
    rtx-4000-ada           NVIDIA RTX 4000 Ada (20GB VRAM)
    rtx-6000-ada           NVIDIA RTX 6000 Ada (48GB VRAM)  
    l40s                   NVIDIA L40S (48GB VRAM)

Examples:
    # Deploy llm-d with RTX 4000 Ada
    $0 -g rtx-4000-ada -t hf_xxxxxxxxxx

    # Deploy llm-d with L40S
    $0 -g l40s -t hf_xxxxxxxxxx

    # Uninstall llm-d
    $0 -u

Environment Variables:
    HF_TOKEN               HuggingFace token (alternative to -t)

Note: 
    This script only deploys llm-d core components.
    For monitoring setup, run: cd monitoring && ./setup-monitoring.sh

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
    print_status "Uninstalling llm-d..."
    
    # Uninstall llm-d
    print_status "Uninstalling llm-d..."
    cd "$QUICKSTART_DIR"
    if ./llmd-installer.sh -u; then
        print_success "llm-d uninstalled successfully"
    else
        print_warning "llm-d uninstall had some issues"
    fi
    
    print_success "🎉 Uninstallation completed!"
}

# Install llm-d
install_llm_d() {
    local config_file="${GPU_CONFIGS_DIR}/${GPU_TYPE}-values.yaml"
    
    print_status "Installing llm-d with GPU configuration: $GPU_TYPE"
    print_status "Using config file: $config_file"
    
    cd "$QUICKSTART_DIR"
    
    # Export HuggingFace token
    export HF_TOKEN="$HUGGINGFACE_TOKEN"
    
    # Install llm-d with GPU-specific configuration
    if ./llmd-installer.sh -f "$config_file"; then
        print_success "llm-d installed successfully"
    else
        print_error "llm-d installation failed"
        exit 1
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    print_status "Waiting for llm-d deployment to be ready..."
    
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
    
    print_success "llm-d deployment is ready"
}

# Show deployment status
show_deployment_status() {
    echo ""
    echo "=================================="
    echo "🎉 Deployment Status"
    echo "=================================="
    echo ""
    
    # llm-d status
    print_status "llm-d Status:"
    kubectl get pods -n llm-d
    echo ""
    
    # Services
    print_status "llm-d Services:"
    kubectl get svc -n llm-d
    echo ""
    
    echo "🧪 Test Commands:"
    echo "  cd ${QUICKSTART_DIR}"
    echo "  ./test-request.sh"
    echo ""
}

# Main execution
main() {
    echo "🚀 llm-d Core Deployment for DigitalOcean Kubernetes"
    echo "===================================================="
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
    print_status "  Config: ${GPU_CONFIGS_DIR}/${GPU_TYPE}-values.yaml"
    echo ""
    
    # Install llm-d
    install_llm_d
    
    # Wait for deployment
    wait_for_deployment
    
    # Show status
    show_deployment_status
    
    print_success "🎉 llm-d deployment completed successfully!"
    echo ""
    echo "💡 Next Steps:"
    echo "  1. Test the deployment: cd ${QUICKSTART_DIR} && ./test-request.sh"
    echo "  2. Setup monitoring (optional): cd monitoring && ./setup-monitoring.sh"
    echo ""
}

# Run main function
main "$@" 