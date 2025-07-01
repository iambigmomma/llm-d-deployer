#!/usr/bin/env bash
# -*- indent-tabs-mode: nil; tab-width: 4; sh-indentation: 4; -*-

set -euo pipefail

### GLOBALS ###
SCRIPT_NAME="$(basename "$0")"
NVIDIA_DEVICE_PLUGIN_NAMESPACE="nvidia-device-plugin"
NVIDIA_DEVICE_PLUGIN_VERSION="v0.17.1"
KUBERNETES_CONTEXT=""
FORCE_REINSTALL=false
DRY_RUN=false

# ANSI color helpers
COLOR_RESET=$'\e[0m'
COLOR_GREEN=$'\e[32m'
COLOR_YELLOW=$'\e[33m'
COLOR_RED=$'\e[31m'
COLOR_BLUE=$'\e[34m'

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

die() {
    log_error "$*"
    exit 1
}

### HELP ###
print_help() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

DigitalOcean GPU Kubernetes Cluster 預安裝腳本
此腳本會安裝並配置 NVIDIA Device Plugin，以及修復 GPU 節點標籤問題，
確保後續的 llmd-installer.sh 可以正常運行。

Options:
  -g, --context PATH           指定 Kubernetes context 文件路径
  -f, --force-reinstall        強制重新安裝 NVIDIA Device Plugin
  -d, --dry-run               只顯示將要執行的操作，不實際執行
  -h, --help                  顯示此幫助信息並退出

Examples:
  ${SCRIPT_NAME}                           # 使用當前 kubectl context
  ${SCRIPT_NAME} -g ~/.kube/config         # 使用指定的 kubeconfig
  ${SCRIPT_NAME} --force-reinstall         # 強制重新安裝
  ${SCRIPT_NAME} --dry-run                 # 預覽將要執行的操作

EOF
}

### ARGUMENT PARSING ###
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--context)
                KUBERNETES_CONTEXT="$2"
                shift 2
                ;;
            -f|--force-reinstall)
                FORCE_REINSTALL=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                die "未知選項: $1"
                ;;
        esac
    done
}

### UTILITIES ###
check_cmd() {
    command -v "$1" &>/dev/null || die "缺少必要命令: $1"
}

check_dependencies() {
    local required_cmds=(kubectl helm)
    for cmd in "${required_cmds[@]}"; do
        check_cmd "$cmd"
    done
}

setup_kubectl() {
    if [[ -n "${KUBERNETES_CONTEXT}" ]]; then
        if [[ ! -f "${KUBERNETES_CONTEXT}" ]]; then
            die "指定的 kubeconfig 文件不存在: ${KUBERNETES_CONTEXT}"
        fi
        KCMD="kubectl --kubeconfig ${KUBERNETES_CONTEXT}"
        HCMD="helm --kubeconfig ${KUBERNETES_CONTEXT}"
        log_info "使用指定的 kubeconfig: ${KUBERNETES_CONTEXT}"
    else
        KCMD="kubectl"
        HCMD="helm"
        log_info "使用當前的 kubectl context"
    fi
}

check_cluster_reachability() {
    log_info "檢查 Kubernetes 集群連接性..."
    if ${KCMD} cluster-info &>/dev/null; then
        log_success "成功連接到 Kubernetes 集群"
    else
        die "無法連接到 Kubernetes 集群，請檢查您的 kubectl 配置"
    fi
}

verify_digitalocean_gpu_cluster() {
    log_info "驗證這是 DigitalOcean GPU 集群..."
    
    # 檢查是否有 GPU 節點
    local gpu_nodes
    gpu_nodes=$(${KCMD} get nodes -l doks.digitalocean.com/gpu-brand=nvidia --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "${gpu_nodes}" -eq 0 ]]; then
        log_warning "未找到 DigitalOcean GPU 節點標籤，檢查節點類型..."
        # 檢查是否有 GPU 實例類型的節點
        gpu_nodes=$(${KCMD} get nodes -o jsonpath='{.items[*].metadata.labels.node\.kubernetes\.io/instance-type}' | grep -c "gpu-" || echo "0")
        
        if [[ "${gpu_nodes}" -eq 0 ]]; then
            die "此集群似乎沒有 GPU 節點。請確認您使用的是 DigitalOcean GPU 集群。"
        fi
    fi
    
    log_success "檢測到 ${gpu_nodes} 個 GPU 節點"
}

get_gpu_nodes() {
    # 優先使用 DigitalOcean 標籤
    local gpu_nodes
    gpu_nodes=$(${KCMD} get nodes -l doks.digitalocean.com/gpu-brand=nvidia -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    # 如果沒有找到，使用實例類型
    if [[ -z "${gpu_nodes}" ]]; then
        gpu_nodes=$(${KCMD} get nodes -o json | jq -r '.items[] | select(.metadata.labels."node.kubernetes.io/instance-type" | test("gpu-")) | .metadata.name' 2>/dev/null || echo "")
    fi
    
    echo "${gpu_nodes}"
}

install_nvidia_device_plugin() {
    log_info "安裝 NVIDIA Device Plugin..."
    
    # 檢查是否已安裝
    if ${KCMD} get namespace "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" &>/dev/null && [[ "${FORCE_REINSTALL}" != "true" ]]; then
        log_warning "NVIDIA Device Plugin 已安裝，使用 --force-reinstall 強制重新安裝"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] 將會安裝 NVIDIA Device Plugin ${NVIDIA_DEVICE_PLUGIN_VERSION}"
        return 0
    fi
    
    # 如果需要重新安裝，先刪除
    if [[ "${FORCE_REINSTALL}" == "true" ]]; then
        log_info "移除現有的 NVIDIA Device Plugin..."
        ${HCMD} uninstall nvdp -n "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" --ignore-not-found || true
        ${KCMD} delete namespace "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" --ignore-not-found || true
        sleep 5
    fi
    
    # 創建 namespace
    ${KCMD} create namespace "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" --dry-run=client -o yaml | ${KCMD} apply -f -
    
    # 添加 NVIDIA Helm repository
    ${HCMD} repo add nvdp https://nvidia.github.io/k8s-device-plugin
    ${HCMD} repo update
    
    # 安裝 NVIDIA Device Plugin
    ${HCMD} install nvdp nvdp/nvidia-device-plugin \
        --namespace "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" \
        --version "${NVIDIA_DEVICE_PLUGIN_VERSION}" \
        --set nodeSelector="nvidia.com/gpu=true" \
        --wait
    
    log_success "NVIDIA Device Plugin 安裝完成"
}

wait_for_device_plugin() {
    log_info "等待 NVIDIA Device Plugin 就緒..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] 將會等待 Device Plugin pods 就緒"
        return 0
    fi
    
    # 等待 DaemonSet 就緒
    local max_attempts=30
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local ready_pods
        ready_pods=$(${KCMD} get daemonset nvdp-nvidia-device-plugin -n "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        local desired_pods
        desired_pods=$(${KCMD} get daemonset nvdp-nvidia-device-plugin -n "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        
        if [[ "${ready_pods}" -gt 0 ]] && [[ "${ready_pods}" -eq "${desired_pods}" ]]; then
            log_success "NVIDIA Device Plugin DaemonSet 已就緒 (${ready_pods}/${desired_pods})"
            return 0
        fi
        
        log_info "等待 Device Plugin DaemonSet 就緒... (${ready_pods}/${desired_pods}) - 嘗試 $((attempt + 1))/${max_attempts}"
        sleep 10
        ((attempt++))
    done
    
    log_warning "Device Plugin DaemonSet 在預期時間內未完全就緒，繼續執行標籤修復..."
}

fix_gpu_node_labels() {
    log_info "修復 GPU 節點標籤..."
    
    local gpu_nodes
    gpu_nodes=$(get_gpu_nodes)
    
    if [[ -z "${gpu_nodes}" ]]; then
        die "未找到 GPU 節點"
    fi
    
    for node in ${gpu_nodes}; do
        log_info "處理節點: ${node}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] 將會為節點 ${node} 添加標籤: feature.node.kubernetes.io/pci-10de.present=true"
            continue
        fi
        
        # 添加必要的標籤
        ${KCMD} label nodes "${node}" feature.node.kubernetes.io/pci-10de.present=true --overwrite
        ${KCMD} label nodes "${node}" nvidia.com/gpu.present=true --overwrite
        
        log_success "節點 ${node} 標籤修復完成"
    done
}

verify_gpu_resources() {
    log_info "驗證 GPU 資源可用性..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] 將會驗證 GPU 資源是否可用"
        return 0
    fi
    
    local gpu_nodes
    gpu_nodes=$(get_gpu_nodes)
    
    local total_gpus=0
    local available_gpus=0
    
    for node in ${gpu_nodes}; do
        local gpu_capacity
        gpu_capacity=$(${KCMD} get node "${node}" -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        local gpu_allocatable
        gpu_allocatable=$(${KCMD} get node "${node}" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        
        if [[ "${gpu_capacity}" -gt 0 ]]; then
            log_success "節點 ${node}: GPU 容量=${gpu_capacity}, 可分配=${gpu_allocatable}"
            total_gpus=$((total_gpus + gpu_capacity))
            available_gpus=$((available_gpus + gpu_allocatable))
        else
            log_warning "節點 ${node}: 未檢測到 GPU 資源"
        fi
    done
    
    if [[ ${total_gpus} -gt 0 ]]; then
        log_success "GPU 資源驗證完成: 總計 ${total_gpus} 個 GPU，可用 ${available_gpus} 個"
    else
        die "未檢測到任何 GPU 資源，請檢查 NVIDIA Device Plugin 安裝"
    fi
}

run_health_check() {
    log_info "執行健康檢查..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] 將會執行完整的健康檢查"
        return 0
    fi
    
    # 檢查 Device Plugin pods
    local plugin_pods
    plugin_pods=$(${KCMD} get pods -n "${NVIDIA_DEVICE_PLUGIN_NAMESPACE}" -l app.kubernetes.io/name=nvidia-device-plugin --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "${plugin_pods}" -gt 0 ]]; then
        log_success "NVIDIA Device Plugin pods: ${plugin_pods} 個正在運行"
    else
        log_warning "未找到運行中的 NVIDIA Device Plugin pods"
    fi
    
    # 檢查 GPU taints 和 tolerations
    local gpu_nodes
    gpu_nodes=$(get_gpu_nodes)
    
    for node in ${gpu_nodes}; do
        local has_gpu_taint
        has_gpu_taint=$(${KCMD} get node "${node}" -o jsonpath='{.spec.taints[?(@.key=="nvidia.com/gpu")].key}' 2>/dev/null || echo "")
        
        if [[ -n "${has_gpu_taint}" ]]; then
            log_success "節點 ${node}: 具有正確的 GPU taint"
        else
            log_warning "節點 ${node}: 缺少 GPU taint，這可能是正常的"
        fi
    done
    
    log_success "健康檢查完成"
}

### MAIN FUNCTION ###
main() {
    parse_args "$@"
    
    log_info "🚀 DigitalOcean GPU Kubernetes Cluster 預安裝腳本"
    log_info "版本: NVIDIA Device Plugin ${NVIDIA_DEVICE_PLUGIN_VERSION}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN 模式 - 不會執行實際操作"
    fi
    
    check_dependencies
    setup_kubectl
    check_cluster_reachability
    verify_digitalocean_gpu_cluster
    
    install_nvidia_device_plugin
    wait_for_device_plugin
    fix_gpu_node_labels
    
    # 等待一下讓資源刷新
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "等待資源刷新..."
        sleep 30
    fi
    
    verify_gpu_resources
    run_health_check
    
    log_success "🎉 DigitalOcean GPU Cluster 預安裝完成！"
    log_info "現在您可以運行 llmd-installer.sh 進行 LLM-D 部署"
}

main "$@" 