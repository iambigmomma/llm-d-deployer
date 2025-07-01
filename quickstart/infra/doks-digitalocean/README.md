# DigitalOcean GPU Kubernetes Cluster - LLM-D 部署指南

## 概述

本指南專門針對在 DigitalOcean GPU Kubernetes Cluster (DOKS) 上部署 LLM-D 的常見問題提供解決方案。主要解決 NVIDIA Device Plugin 配置問題，確保 GPU 資源能夠正確分配給 LLM-D 的 prefill 和 decode pods。

## 問題背景

### 常見症狀

當在 DigitalOcean GPU Kubernetes Cluster 上運行 `llmd-installer.sh` 時，您可能會遇到以下問題：

1. **Prefill 和 Decode Pods 卡在 Pending 狀態**

   ```
   NAME                      READY   STATUS    RESTARTS
   prefill-deployment-xxx    0/1     Pending   0
   decode-deployment-xxx     0/2     Pending   0
   ```

2. **Pod 事件顯示資源不足**

   ```
   Events:
   Warning  FailedScheduling  pod/prefill-deployment-xxx
   0/2 nodes are available: 2 Insufficient nvidia.com/gpu.
   ```

3. **GPU 節點沒有可用的 GPU 資源**
   ```bash
   kubectl describe node <gpu-node>
   # Allocatable 部分缺少 nvidia.com/gpu
   ```

### 根本原因

DigitalOcean GPU Kubernetes Cluster 的 GPU 節點缺少必要的 Node Feature Discovery (NFD) 標籤，導致 NVIDIA Device Plugin 無法正確調度到 GPU 節點上：

- **缺少標籤**: `feature.node.kubernetes.io/pci-10de.present=true`
- **影響**: NVIDIA Device Plugin DaemonSet 無法在 GPU 節點上運行
- **結果**: GPU 節點無法暴露 `nvidia.com/gpu` 資源

## 解決方案

### 自動化腳本

我們提供了一個全自動的預安裝腳本來解決這個問題：

```bash
./setup-gpu-cluster.sh
```

### 腳本功能

1. **環境驗證**

   - 檢查必要的工具 (kubectl, helm)
   - 驗證 Kubernetes 集群連接性
   - 確認這是 DigitalOcean GPU 集群

2. **NVIDIA Device Plugin 安裝**

   - 使用 Helm 安裝最新版本的 NVIDIA Device Plugin
   - 自動配置必要的 namespace 和設置
   - 等待 DaemonSet 準備就緒

3. **GPU 節點標籤修復**

   - 自動檢測所有 GPU 節點
   - 添加必要的 NFD 標籤
   - 確保 Device Plugin 能夠調度

4. **資源驗證**
   - 驗證 GPU 資源正確暴露
   - 執行健康檢查
   - 確認系統就緒

## 使用方法

### 基本用法

```bash
# 克隆項目並進入目錄
cd quickstart/infra/doks-digitalocean

# 賦予執行權限
chmod +x setup-gpu-cluster.sh

# 運行腳本
./setup-gpu-cluster.sh
```

### 高級選項

```bash
# 使用自定義 kubeconfig
./setup-gpu-cluster.sh --context ~/.kube/my-cluster-config

# 強制重新安裝 NVIDIA Device Plugin
./setup-gpu-cluster.sh --force-reinstall

# 預覽模式 (不執行實際操作)
./setup-gpu-cluster.sh --dry-run

# 查看幫助
./setup-gpu-cluster.sh --help
```

### 預期輸出

成功運行後，您應該看到類似以下的輸出：

```
🚀 DigitalOcean GPU Kubernetes Cluster 預安裝腳本
版本: NVIDIA Device Plugin v0.17.1

ℹ️  使用當前的 kubectl context
✅ 成功連接到 Kubernetes 集群
✅ 檢測到 2 個 GPU 節點
ℹ️  安裝 NVIDIA Device Plugin...
✅ NVIDIA Device Plugin 安裝完成
✅ NVIDIA Device Plugin DaemonSet 已就緒 (2/2)
ℹ️  修復 GPU 節點標籤...
✅ 節點 pool-xxx-1 標籤修復完成
✅ 節點 pool-xxx-2 標籤修復完成
✅ GPU 資源驗證完成: 總計 2 個 GPU，可用 2 個
✅ 健康檢查完成
🎉 DigitalOcean GPU Cluster 預安裝完成！
ℹ️  現在您可以運行 llmd-installer.sh 進行 LLM-D 部署
```

## 手動解決方案

如果您不想使用自動化腳本，也可以手動執行以下步驟：

### 1. 安裝 NVIDIA Device Plugin

```bash
# 創建 namespace
kubectl create namespace nvidia-device-plugin

# 添加 Helm repository
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update

# 安裝 Device Plugin
helm install nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin \
  --version v0.17.1 \
  --wait
```

### 2. 識別 GPU 節點

```bash
# 方法 1: 使用 DigitalOcean 標籤
kubectl get nodes -l doks.digitalocean.com/gpu-brand=nvidia

# 方法 2: 使用實例類型
kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."node.kubernetes.io/instance-type" | test("gpu-")) | .metadata.name'
```

### 3. 添加必要標籤

```bash
# 為每個 GPU 節點添加標籤
kubectl label nodes <gpu-node-1> feature.node.kubernetes.io/pci-10de.present=true
kubectl label nodes <gpu-node-2> feature.node.kubernetes.io/pci-10de.present=true

# 可選：添加額外的 GPU 標籤
kubectl label nodes <gpu-node-1> nvidia.com/gpu.present=true
kubectl label nodes <gpu-node-2> nvidia.com/gpu.present=true
```

### 4. 驗證配置

```bash
# 檢查 Device Plugin pods
kubectl get pods -n nvidia-device-plugin

# 驗證 GPU 資源
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'

# 檢查節點詳細信息
kubectl describe node <gpu-node-name>
```

## 部署 LLM-D

預安裝完成後，您可以正常運行 LLM-D 安裝腳本：

```bash
# 返回到項目根目錄
cd ../../..

# 運行 LLM-D 安裝腳本
./llmd-installer.sh
```

## 故障排除

### Device Plugin Pods 無法啟動

```bash
# 檢查 DaemonSet 狀態
kubectl get daemonset -n nvidia-device-plugin

# 查看 Pod 事件
kubectl describe pods -n nvidia-device-plugin

# 檢查節點標籤
kubectl get nodes --show-labels | grep feature.node.kubernetes.io/pci
```

### GPU 資源仍然不可用

```bash
# 重啟 Device Plugin
kubectl rollout restart daemonset/nvdp-nvidia-device-plugin -n nvidia-device-plugin

# 等待 pods 重新啟動
kubectl rollout status daemonset/nvdp-nvidia-device-plugin -n nvidia-device-plugin

# 重新檢查資源
kubectl get nodes -o yaml | grep -A 10 -B 10 "nvidia.com/gpu"
```

### LLM-D Pods 仍然 Pending

```bash
# 檢查 pods 事件
kubectl describe pod -n llm-d -l llm-d.ai/inferenceServing=true

# 檢查資源請求
kubectl get pod -n llm-d -o yaml | grep -A 5 -B 5 "nvidia.com/gpu"

# 驗證 Tolerations
kubectl get pod -n llm-d -o yaml | grep -A 10 tolerations
```

## 技術細節

### NVIDIA Device Plugin 工作原理

1. **Device Plugin** 作為 DaemonSet 運行在每個 GPU 節點上
2. **Node Affinity** 要求節點具有特定標籤才能調度
3. **Resource Advertising** 向 Kubernetes API 暴露 GPU 資源
4. **Resource Allocation** 為請求 GPU 的 pods 分配設備

### DigitalOcean GPU 節點特性

- **實例類型**: 通常包含 "gpu-" 前綴
- **GPU 品牌**: NVIDIA Tesla 系列
- **驅動程序**: 預安裝 NVIDIA 驅動
- **容器運行時**: 支持 NVIDIA Container Runtime

### 標籤說明

| 標籤                                               | 用途                  | 來源                |
| -------------------------------------------------- | --------------------- | ------------------- |
| `feature.node.kubernetes.io/pci-10de.present=true` | NVIDIA PCI 設備檢測   | NFD 或手動添加      |
| `nvidia.com/gpu.present=true`                      | GPU 存在標識          | 手動添加            |
| `doks.digitalocean.com/gpu-brand=nvidia`           | DigitalOcean GPU 品牌 | DOKS 自動添加       |
| `node.kubernetes.io/instance-type`                 | 節點實例類型          | Kubernetes 自動添加 |

## 支持的 DigitalOcean GPU 實例

| 實例類型                     | GPU 型號     | GPU 數量 | 記憶體 |
| ---------------------------- | ------------ | -------- | ------ |
| `gpu-nvidia-rtx-4000-ada-x1` | RTX 4000 Ada | 1        | 20GB   |
| `gpu-nvidia-rtx-4000-ada-x2` | RTX 4000 Ada | 2        | 40GB   |
| `gpu-nvidia-rtx-4000-ada-x4` | RTX 4000 Ada | 4        | 80GB   |
| `gpu-nvidia-h100-x1`         | H100         | 1        | 80GB   |
| `gpu-nvidia-h100-x2`         | H100         | 2        | 160GB  |
| `gpu-nvidia-h100-x4`         | H100         | 4        | 320GB  |
| `gpu-nvidia-h100-x8`         | H100         | 8        | 640GB  |

## 最佳實踐

### 1. 資源規劃

- **每個 GPU** 只能被單個 pod 使用
- **Prefill Pod** 通常需要 1 個 GPU
- **Decode Pod** 可能需要 1-2 個 GPU (取決於配置)
- **預留資源** 為系統和其他服務留出空間

### 2. 監控和維護

```bash
# 定期檢查 GPU 使用率
kubectl top nodes

# 監控 Device Plugin 狀態
kubectl get pods -n nvidia-device-plugin -w

# 檢查資源分配
kubectl describe nodes | grep -A 5 -B 5 "nvidia.com/gpu"
```

### 3. 升級和更新

```bash
# 更新 Device Plugin
helm upgrade nvdp nvdp/nvidia-device-plugin -n nvidia-device-plugin

# 檢查可用版本
helm search repo nvdp
```

## 相關資源

- [NVIDIA Device Plugin 官方文檔](https://github.com/NVIDIA/k8s-device-plugin)
- [DigitalOcean GPU Kubernetes 服務](https://docs.digitalocean.com/products/kubernetes/how-to/add-gpu-nodes/)
- [Kubernetes GPU 調度](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
- [Node Feature Discovery](https://kubernetes-sigs.github.io/node-feature-discovery/)

## 常見問題 (FAQ)

### Q: 為什麼需要手動添加標籤？

A: DigitalOcean 的 GPU 節點沒有預裝 Node Feature Discovery (NFD)，因此缺少 NVIDIA Device Plugin 所需的 PCI 設備標籤。

### Q: 這個解決方案是否適用於其他雲服務提供商？

A: 此解決方案專門針對 DigitalOcean 設計，其他雲服務提供商可能有不同的配置需求。

### Q: 如何確認 GPU 驅動程序正確安裝？

A: 可以在 GPU 節點上運行 `nvidia-smi` 命令，或檢查 Device Plugin pods 的日誌。

### Q: Device Plugin 重啟會影響正在運行的 pods 嗎？

A: 不會。Device Plugin 重啟不會影響已經分配了 GPU 資源的運行中 pods。

### Q: 可以在同一個集群上運行多個 LLM-D 實例嗎？

A: 可以，但需要確保有足夠的 GPU 資源，並且每個實例使用不同的 namespace。

## 🚀 Quick Start with Pre-configured GPU Settings

### GPU Configuration Files

We provide optimized configuration files for different GPU models:

| GPU Model           | VRAM | Configuration File                     | Max Sequence Length |
| ------------------- | ---- | -------------------------------------- | ------------------- |
| NVIDIA RTX 4000 Ada | 20GB | `gpu-configs/rtx-4000-ada-values.yaml` | 8,192               |
| NVIDIA RTX 6000 Ada | 48GB | `gpu-configs/rtx-6000-ada-values.yaml` | 16,384              |
| NVIDIA L40S         | 48GB | `gpu-configs/l40s-values.yaml`         | 20,480              |

### One-Command Deployment

Use the unified deployment script with monitoring:

```bash
# Deploy with RTX 4000 Ada
./deploy-with-monitoring.sh -g rtx-4000-ada -t your_hf_token_here

# Deploy with RTX 6000 Ada
./deploy-with-monitoring.sh -g rtx-6000-ada -t your_hf_token_here

# Deploy with L40S
./deploy-with-monitoring.sh -g l40s -t your_hf_token_here

# Deploy without monitoring
./deploy-with-monitoring.sh -g rtx-4000-ada -t your_hf_token_here -m
```

### Manual Deployment

If you prefer manual deployment:

```bash
# Go to quickstart directory
cd ../../

# Set your HuggingFace token
export HF_TOKEN=your_token_here

# Deploy with specific GPU configuration
./llmd-installer.sh -f infra/doks-digitalocean/gpu-configs/rtx-4000-ada-values.yaml

# Set up monitoring (optional)
cd infra/doks-digitalocean/monitoring
./setup-monitoring.sh
```

## 📊 Monitoring and Dashboards

### Included Monitoring Stack

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization dashboards
- **AlertManager**: Alert handling
- **Node Exporter**: Node-level metrics
- **Custom LLM-D Dashboard**: Inference-specific metrics

### Monitoring Setup

The monitoring system is automatically installed with the deployment script, or you can install it separately:

```bash
cd infra/doks-digitalocean/monitoring
chmod +x setup-monitoring.sh
./setup-monitoring.sh
```

### Access Monitoring

```bash
# Access Grafana
kubectl port-forward -n llm-d-monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000
# Username: admin, Password: admin

# Access Prometheus
kubectl port-forward -n llm-d-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090
```

### Monitoring Metrics

The LLM-D dashboard includes:

- **Active Pods**: Number of running model service pods
- **Request Rate**: Inference requests per second
- **Response Time**: Average latency and percentiles
- **GPU Memory Usage**: Memory utilization across pods
- **Token Throughput**: Tokens processed per second
- **Queue Status**: Request queue depth
- **Error Rates**: Failed request monitoring

## 🔧 GPU Configuration Details

### RTX 4000 Ada (20GB VRAM)

```yaml
# Memory-optimized for 20GB VRAM
sampleApplication:
  decode:
    extraArgs:
      - "--max-model-len"
      - "8192" # Reduced for memory efficiency
      - "--gpu-memory-utilization"
      - "0.85" # Use 85% of GPU memory
      - "--enforce-eager" # Disable CUDA graph
  # ... resource limits: 1 GPU, 32Gi memory, 8 CPU cores
```

### RTX 6000 Ada (48GB VRAM)

```yaml
# Optimized for 48GB VRAM
sampleApplication:
  decode:
    extraArgs:
      - "--max-model-len"
      - "16384" # Higher sequence length
      - "--gpu-memory-utilization"
      - "0.85"
      - "--kv-cache-dtype"
      - "fp8" # Memory-efficient cache
  # ... resource limits: 1 GPU, 64Gi memory, 16 CPU cores
```

### L40S (48GB VRAM)

```yaml
# High-performance configuration
sampleApplication:
  decode:
    extraArgs:
      - "--max-model-len"
      - "20480" # Maximum sequence length
      - "--gpu-memory-utilization"
      - "0.85"
      - "--kv-cache-dtype"
      - "fp8"
  # ... resource limits: 1 GPU, 96Gi memory, 24 CPU cores
```

## 📋 Management Commands

### Deployment Script Options

```bash
./deploy-with-monitoring.sh [OPTIONS]

Options:
    -g, --gpu TYPE          GPU type (rtx-4000-ada, rtx-6000-ada, l40s)
    -t, --token TOKEN       HuggingFace token (required)
    -m, --no-monitoring     Skip monitoring installation
    -u, --uninstall         Uninstall LLM-D and monitoring
    -h, --help              Show help message
```

### Uninstall Everything

```bash
# Uninstall LLM-D and monitoring
./deploy-with-monitoring.sh -u

# Or manually
cd ../../
./llmd-installer.sh -u
helm uninstall prometheus -n llm-d-monitoring
kubectl delete namespace llm-d-monitoring
```

### Testing the Deployment

```bash
# Run comprehensive tests
cd ../../
./test-request.sh

# Manual testing
# Get gateway IP
kubectl get svc -n istio-system istio-ingressgateway

# Test models endpoint
curl -H "Host: inference.example.com" http://<GATEWAY_IP>/v1/models

# Test completion
curl -H "Host: inference.example.com" http://<GATEWAY_IP>/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.2-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 100
  }'
```

## 🔍 Troubleshooting

### Common Issues

1. **GPU Memory Issues**

   - Check GPU memory usage: `kubectl logs -n llm-d <pod-name> -c vllm`
   - Reduce `max-model-len` if out of memory
   - Lower `gpu-memory-utilization` value

2. **Pod Not Starting**

   - Check events: `kubectl describe pod -n llm-d <pod-name>`
   - Verify HuggingFace token: `kubectl get secret -n llm-d`
   - Check resource availability: `kubectl describe nodes`

3. **Monitoring Issues**
   - Check monitoring pods: `kubectl get pods -n llm-d-monitoring`
   - Verify ServiceMonitor: `kubectl get servicemonitor -n llm-d-monitoring`
   - Check Prometheus targets: Access Prometheus UI → Status → Targets

### Logs and Debugging

```bash
# LLM-D application logs
kubectl logs -n llm-d deployment/meta-llama-llama-3-2-3b-instruct-decode -c vllm

# Gateway logs
kubectl logs -n istio-system deployment/istio-ingressgateway

# Monitoring logs
kubectl logs -n llm-d-monitoring deployment/prometheus-grafana
kubectl logs -n llm-d-monitoring statefulset/prometheus-prometheus-kube-prometheus-prometheus
```

### Performance Tuning

1. **Memory Optimization**

   - Adjust `gpu-memory-utilization` (0.7-0.95)
   - Use `fp8` for KV cache on supported models
   - Enable `enforce-eager` for memory savings

2. **Throughput Optimization**

   - Increase `max-model-len` if memory allows
   - Disable `enforce-eager` for better performance
   - Adjust batch sizes based on workload

3. **Resource Allocation**
   - Monitor CPU and memory usage in Grafana
   - Adjust resource requests/limits based on actual usage
   - Consider multi-GPU setup for larger models

## 📚 Additional Resources

- [Original DOKS Setup Guide](setup-gpu-cluster.sh)
- [LLM-D Documentation](../../README.md)
- [Kubernetes GPU Guide](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Documentation](https://grafana.com/docs/)

## 🤝 Contributing

When adding new GPU configurations:

1. Create a new values file in `gpu-configs/`
2. Update the deployment script with the new GPU type
3. Add monitoring configurations if needed
4. Update this README with the new GPU specifications
5. Test thoroughly with the new configuration
