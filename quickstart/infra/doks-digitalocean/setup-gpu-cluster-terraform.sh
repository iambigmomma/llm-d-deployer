#!/usr/bin/env bash
# -*- indent-tabs-mode: nil; tab-width: 4; sh-indentation: 4; -*-

set -euo pipefail

### GLOBALS ###
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

# Default configuration
CLUSTER_NAME="llm-d-cluster"
CLUSTER_REGION="tor1"
GPU_TYPE="rtx-6000-ada"
USE_DEFAULT_VPC=true
DRY_RUN=false
AUTO_APPROVE=false
DESTROY=false
VARS_FILE=""

# ANSI color helpers
COLOR_RESET=$'\e[0m'
COLOR_GREEN=$'\e[32m'
COLOR_YELLOW=$'\e[33m'
COLOR_RED=$'\e[31m'
COLOR_BLUE=$'\e[34m'
COLOR_CYAN=$'\e[36m'
COLOR_PURPLE=$'\e[35m'

log_info() {
    echo "${COLOR_BLUE}ℹ️  $*${COLOR_RESET}"
}

log_success() {
    echo "${COLOR_GREEN}✅ $*${COLOR_RESET}"
}

log_warning() {
    echo "${COLOR_YELLOW}⚠️  $*${COLOR_RESET}"
}

log_error() {
    echo "${COLOR_RED}❌ $*${COLOR_RESET}" >&2
}

log_step() {
    echo "${COLOR_PURPLE}🔹 $*${COLOR_RESET}"
}

log_cluster() {
    echo "${COLOR_CYAN}🚀 $*${COLOR_RESET}"
}

die() {
    log_error "$*"
    exit 1
}

### HELP ###
print_help() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

DigitalOcean GPU Kubernetes Cluster Setup with Terraform
This script uses Terraform to create a complete DOKS cluster with GPU support for llm-d deployment.

🧠 SMART FEATURES:
  • Infrastructure as Code using Terraform
  • Reproducible and version-controlled deployments
  • State management for safe updates and rollbacks
  • Parallel resource creation for faster deployment
  • Comprehensive output with next steps and cost estimates

Options:
  -n, --cluster-name NAME      Cluster name (default: ${CLUSTER_NAME})
  -r, --region REGION          DigitalOcean region (default: ${CLUSTER_REGION})
  -g, --gpu-type TYPE          GPU type: rtx-4000-ada, rtx-6000-ada, l40s (default: ${GPU_TYPE})
  -v, --custom-vpc             Create a custom VPC (default: use default VPC)
  -f, --vars-file FILE         Use custom terraform.tfvars file
  -y, --auto-approve           Auto-approve Terraform plan (non-interactive)
  -d, --dry-run               Show Terraform plan without applying
      --destroy               Destroy the infrastructure
  -h, --help                  Show this help message and exit

GPU Type Mapping:
  rtx-4000-ada    →  gpu-4000adax1-48gb  (~\$700/month)
  rtx-6000-ada    →  gpu-6000adax1-48gb  (~\$1000/month)
  l40s            →  gpu-l40sx1-48gb     (~\$1400/month)

Examples:
  ${SCRIPT_NAME}                                    # Create cluster with default settings
  ${SCRIPT_NAME} -g l40s -r nyc1                   # Create with L40S GPUs in NYC
  ${SCRIPT_NAME} -n my-cluster -v -y               # Custom name, VPC, auto-approve
  ${SCRIPT_NAME} -f my-config.tfvars               # Use custom variables file
  ${SCRIPT_NAME} -d                                # Show plan without applying
  ${SCRIPT_NAME} --destroy                         # Destroy infrastructure

Prerequisites:
  - doctl CLI installed and authenticated
  - terraform CLI installed
  - kubectl CLI installed
  - DigitalOcean Personal Access Token

Environment Variables:
  DO_TOKEN               DigitalOcean token (required if not in tfvars)
  TF_VAR_do_token        Alternative way to set DO token

EOF
}

### ARGUMENT PARSING ###
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -r|--region)
                CLUSTER_REGION="$2"
                shift 2
                ;;
            -g|--gpu-type)
                GPU_TYPE="$2"
                shift 2
                ;;
            -v|--custom-vpc)
                USE_DEFAULT_VPC=false
                shift
                ;;
            -f|--vars-file)
                VARS_FILE="$2"
                shift 2
                ;;
            -y|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --destroy)
                DESTROY=true
                shift
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

### UTILITIES ###
check_dependencies() {
    local required_cmds=(terraform doctl kubectl)
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            die "Required command not found: $cmd"
        fi
    done
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
    log_info "Using Terraform version: ${tf_version}"
    
    # Check doctl authentication
    if ! doctl account get &>/dev/null; then
        die "doctl is not authenticated. Please run: doctl auth init"
    fi
    log_success "doctl authentication verified"
}

map_gpu_type() {
    case "${GPU_TYPE}" in
        rtx-4000-ada)
            echo "gpu-4000adax1-48gb"
            ;;
        rtx-6000-ada)
            echo "gpu-6000adax1-48gb"
            ;;
        l40s)
            echo "gpu-l40sx1-48gb"
            ;;
        *)
            die "Unknown GPU type: ${GPU_TYPE}. Supported: rtx-4000-ada, rtx-6000-ada, l40s"
            ;;
    esac
}

setup_terraform_vars() {
    local gpu_node_size
    gpu_node_size=$(map_gpu_type)
    
    if [[ -n "${VARS_FILE}" ]]; then
        if [[ ! -f "${VARS_FILE}" ]]; then
            die "Specified vars file does not exist: ${VARS_FILE}"
        fi
        log_info "Using custom variables file: ${VARS_FILE}"
        return 0
    fi
    
    # Create temporary tfvars file
    VARS_FILE="${TERRAFORM_DIR}/generated.tfvars"
    
    cat > "${VARS_FILE}" <<EOF
# Auto-generated configuration
cluster_name   = "${CLUSTER_NAME}"
cluster_region = "${CLUSTER_REGION}"
gpu_node_size  = "${gpu_node_size}"
use_default_vpc = ${USE_DEFAULT_VPC}

# Use environment variable for DO token
# Set: export TF_VAR_do_token=your_token_here
EOF

    log_info "Generated Terraform variables file: ${VARS_FILE}"
}

check_do_token() {
    if [[ -z "${TF_VAR_do_token:-}" ]] && [[ -z "${DO_TOKEN:-}" ]]; then
        log_warning "DigitalOcean token not found in environment"
        log_info "Please set one of the following:"
        log_info "  export TF_VAR_do_token=your_digitalocean_token"
        log_info "  export DO_TOKEN=your_digitalocean_token"
        log_info "Or include 'do_token' in your tfvars file"
        echo ""
        read -p "Do you want to enter your token now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter your DigitalOcean token: " -s DO_TOKEN
            echo
            export TF_VAR_do_token="${DO_TOKEN}"
        else
            die "DigitalOcean token is required"
        fi
    elif [[ -n "${DO_TOKEN:-}" ]] && [[ -z "${TF_VAR_do_token:-}" ]]; then
        export TF_VAR_do_token="${DO_TOKEN}"
    fi
}

init_terraform() {
    log_step "Initializing Terraform..."
    
    cd "${TERRAFORM_DIR}"
    
    terraform init
    log_success "Terraform initialized successfully"
}

validate_terraform() {
    log_step "Validating Terraform configuration..."
    
    cd "${TERRAFORM_DIR}"
    
    terraform validate
    log_success "Terraform configuration is valid"
}

plan_terraform() {
    log_step "Creating Terraform execution plan..."
    
    cd "${TERRAFORM_DIR}"
    
    local plan_args=()
    if [[ -n "${VARS_FILE}" ]]; then
        plan_args+=("-var-file=${VARS_FILE}")
    fi
    
    terraform plan "${plan_args[@]}"
    log_success "Terraform plan completed"
}

apply_terraform() {
    log_step "Applying Terraform configuration..."
    
    cd "${TERRAFORM_DIR}"
    
    local apply_args=()
    if [[ -n "${VARS_FILE}" ]]; then
        apply_args+=("-var-file=${VARS_FILE}")
    fi
    
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        apply_args+=("-auto-approve")
    fi
    
    terraform apply "${apply_args[@]}"
    log_success "Terraform apply completed"
}

destroy_terraform() {
    log_step "Destroying Terraform-managed infrastructure..."
    
    cd "${TERRAFORM_DIR}"
    
    local destroy_args=()
    if [[ -n "${VARS_FILE}" ]]; then
        destroy_args+=("-var-file=${VARS_FILE}")
    fi
    
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        destroy_args+=("-auto-approve")
    fi
    
    terraform destroy "${destroy_args[@]}"
    log_success "Infrastructure destroyed"
}

show_outputs() {
    log_step "Displaying cluster information..."
    
    cd "${TERRAFORM_DIR}"
    
    # Show formatted outputs
    echo ""
    terraform output next_steps
    echo ""
    
    log_cluster "Cost Estimation:"
    terraform output -json estimated_monthly_cost | jq -r 'to_entries[] | "\(.key): \(.value)"'
    echo ""
}

cleanup_temp_files() {
    if [[ -f "${TERRAFORM_DIR}/generated.tfvars" ]]; then
        rm -f "${TERRAFORM_DIR}/generated.tfvars"
        log_info "Cleaned up temporary files"
    fi
}

display_prerequisites() {
    log_cluster "📋 Prerequisites Check:"
    echo ""
    echo "  Required tools:"
    
    # Check each tool
    for tool in terraform doctl kubectl; do
        if command -v "$tool" &>/dev/null; then
            local version
            case "$tool" in
                terraform)
                    version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || echo "unknown")
                    ;;
                doctl)
                    version=$(doctl version 2>/dev/null | grep "doctl version" | awk '{print $3}' || echo "unknown")
                    ;;
                kubectl)
                    version=$(kubectl version --client=true -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' || echo "unknown")
                    ;;
            esac
            echo "    ✅ $tool (${version})"
        else
            echo "    ❌ $tool (not found)"
        fi
    done
    
    echo ""
    echo "  Authentication:"
    if doctl account get &>/dev/null; then
        local account_email
        account_email=$(doctl account get -o json | jq -r '.[0].email' 2>/dev/null || echo "unknown")
        echo "    ✅ DigitalOcean (${account_email})"
    else
        echo "    ❌ DigitalOcean (not authenticated)"
    fi
    
    echo ""
}

### MAIN FUNCTION ###
main() {
    parse_args "$@"
    
    log_cluster "🚀 DigitalOcean GPU Kubernetes Cluster Setup (Terraform)"
    echo ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - Will show Terraform plan only"
    elif [[ "${DESTROY}" == "true" ]]; then
        log_warning "DESTROY MODE - Will destroy existing infrastructure"
    fi
    
    display_prerequisites
    check_dependencies
    check_do_token
    
    # Setup variables
    setup_terraform_vars
    
    # Initialize Terraform
    init_terraform
    validate_terraform
    
    if [[ "${DESTROY}" == "true" ]]; then
        # Destroy mode
        log_cluster "🗑️  Destroying Infrastructure"
        echo ""
        destroy_terraform
        
    elif [[ "${DRY_RUN}" == "true" ]]; then
        # Dry run mode
        log_cluster "📋 Terraform Plan (Dry Run)"
        echo ""
        plan_terraform
        
    else
        # Normal deployment mode
        log_cluster "🏗️  Creating GPU Cluster Infrastructure"
        echo ""
        
        # Show configuration summary
        local gpu_node_size
        gpu_node_size=$(map_gpu_type)
        
        echo "📊 Deployment Configuration:"
        echo "   Cluster Name: ${CLUSTER_NAME}"
        echo "   Region: ${CLUSTER_REGION}"
        echo "   GPU Type: ${GPU_TYPE} (${gpu_node_size})"
        echo "   VPC: $(${USE_DEFAULT_VPC} && echo "Default" || echo "Custom")"
        echo "   Auto-approve: ${AUTO_APPROVE}"
        echo ""
        
        if [[ "${AUTO_APPROVE}" != "true" ]]; then
            plan_terraform
            echo ""
            read -p "Do you want to apply this plan? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled"
                cleanup_temp_files
                exit 0
            fi
        fi
        
        apply_terraform
        show_outputs
    fi
    
    cleanup_temp_files
    
    if [[ "${DESTROY}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        echo ""
        log_success "🎉 Cluster deployment completed successfully!"
        echo ""
        log_cluster "🔄 Infrastructure as Code Benefits:"
        echo "  • 📋 All infrastructure is version controlled"
        echo "  • 🔄 Repeatable deployments across environments"
        echo "  • 📊 State tracking for safe updates"
        echo "  • 🗑️  Clean destruction with: $0 --destroy"
        echo ""
        log_cluster "📁 Terraform State:"
        echo "  • State file: ${TERRAFORM_DIR}/terraform.tfstate"
        echo "  • View current state: cd ${TERRAFORM_DIR} && terraform show"
        echo "  • Update infrastructure: Modify tfvars and re-run"
        echo ""
    fi
}

# Trap for cleanup
trap cleanup_temp_files EXIT

# Run main function
main "$@" 