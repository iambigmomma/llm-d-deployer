#!/bin/bash

# LLM-D Examples for DigitalOcean Kubernetes
# This script provides examples of how to use different GPU configurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_example() {
    echo -e "${GREEN}Example $1:${NC} $2"
    echo -e "${YELLOW}Command:${NC}"
    echo "  $3"
    echo ""
}

print_header "🚀 LLM-D Deployment Examples for DigitalOcean"

echo "Before running any deployment, make sure you have:"
echo "✅ A DigitalOcean Kubernetes cluster with GPU nodes"
echo "✅ kubectl configured to access your cluster"
echo "✅ Helm installed"
echo "✅ Your HuggingFace token"
echo ""

print_header "📋 Quick Deployment Examples"

print_example "1" "Deploy with RTX 4000 Ada (20GB VRAM)" \
    "./deploy-with-monitoring.sh -g rtx-4000-ada -t your_hf_token_here"

print_example "2" "Deploy with RTX 6000 Ada (48GB VRAM)" \
    "./deploy-with-monitoring.sh -g rtx-6000-ada -t your_hf_token_here"

print_example "3" "Deploy with L40S (48GB VRAM)" \
    "./deploy-with-monitoring.sh -g l40s -t your_hf_token_here"

print_example "4" "Deploy without monitoring" \
    "./deploy-with-monitoring.sh -g rtx-4000-ada -t your_hf_token_here -m"

print_header "🔧 Manual Deployment Examples"

echo -e "${GREEN}Example 5:${NC} Manual deployment with specific GPU config"
echo -e "${YELLOW}Commands:${NC}"
echo "  cd ../../"
echo "  export HF_TOKEN=your_token_here"
echo "  ./llmd-installer.sh -f infra/doks-digitalocean/gpu-configs/rtx-4000-ada-values.yaml"
echo ""

echo -e "${GREEN}Example 6:${NC} Setup monitoring only"
echo -e "${YELLOW}Commands:${NC}"
echo "  cd monitoring"
echo "  ./setup-monitoring.sh"
echo ""

print_header "📊 Monitoring Access Examples"

echo -e "${GREEN}Example 7:${NC} Access Grafana dashboard"
echo -e "${YELLOW}Commands:${NC}"
echo "  kubectl port-forward -n llm-d-monitoring svc/prometheus-grafana 3000:80"
echo "  # Open http://localhost:3000 (admin/admin)"
echo ""

echo -e "${GREEN}Example 8:${NC} Access Prometheus"
echo -e "${YELLOW}Commands:${NC}"
echo "  kubectl port-forward -n llm-d-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "  # Open http://localhost:9090"
echo ""

print_header "🧪 Testing Examples"

echo -e "${GREEN}Example 9:${NC} Run comprehensive tests"
echo -e "${YELLOW}Commands:${NC}"
echo "  cd ../../"
echo "  ./test-request.sh"
echo ""

echo -e "${GREEN}Example 10:${NC} Manual API testing"
echo -e "${YELLOW}Commands:${NC}"
echo "  # Get gateway IP"
echo "  GATEWAY_IP=\$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo ""
echo "  # Test models endpoint"
echo "  curl -H \"Host: inference.example.com\" http://\$GATEWAY_IP/v1/models"
echo ""
echo "  # Test completion"
echo "  curl -H \"Host: inference.example.com\" http://\$GATEWAY_IP/v1/completions \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{"
echo "      \"model\": \"meta-llama/Llama-3.2-3B-Instruct\","
echo "      \"prompt\": \"Hello, how are you?\","
echo "      \"max_tokens\": 100"
echo "    }'"
echo ""

print_header "🔍 Debugging Examples"

echo -e "${GREEN}Example 11:${NC} Check deployment status"
echo -e "${YELLOW}Commands:${NC}"
echo "  kubectl get pods -n llm-d"
echo "  kubectl get svc -n llm-d"
echo "  kubectl describe pod -n llm-d \$(kubectl get pods -n llm-d -o name | head -1)"
echo ""

echo -e "${GREEN}Example 12:${NC} View logs"
echo -e "${YELLOW}Commands:${NC}"
echo "  # VLLM logs"
echo "  kubectl logs -n llm-d deployment/meta-llama-llama-3-2-3b-instruct-decode -c vllm"
echo ""
echo "  # Routing proxy logs"
echo "  kubectl logs -n llm-d deployment/meta-llama-llama-3-2-3b-instruct-decode -c routing-proxy"
echo ""

echo -e "${GREEN}Example 13:${NC} Check GPU usage"
echo -e "${YELLOW}Commands:${NC}"
echo "  # Get pod name"
echo "  POD_NAME=\$(kubectl get pods -n llm-d -l app.kubernetes.io/name=modelservice -o jsonpath='{.items[0].metadata.name}')"
echo ""
echo "  # Check GPU memory"
echo "  kubectl exec -n llm-d \$POD_NAME -c vllm -- nvidia-smi"
echo ""

print_header "♻️ Cleanup Examples"

echo -e "${GREEN}Example 14:${NC} Uninstall everything"
echo -e "${YELLOW}Commands:${NC}"
echo "  ./deploy-with-monitoring.sh -u"
echo ""

echo -e "${GREEN}Example 15:${NC} Manual cleanup"
echo -e "${YELLOW}Commands:${NC}"
echo "  cd ../../"
echo "  ./llmd-installer.sh -u"
echo "  helm uninstall prometheus -n llm-d-monitoring"
echo "  kubectl delete namespace llm-d-monitoring"
echo ""

print_header "⚙️ Configuration Customization Examples"

echo -e "${GREEN}Example 16:${NC} Custom memory settings for RTX 4000 Ada"
echo -e "${YELLOW}Create custom-rtx-4000.yaml:${NC}"
echo "sampleApplication:"
echo "  decode:"
echo "    extraArgs:"
echo "      - \"--max-model-len\""
echo "      - \"6144\"                    # Even more conservative"
echo "      - \"--gpu-memory-utilization\""
echo "      - \"0.80\"                    # Use only 80% of GPU memory"
echo "      - \"--enforce-eager\""
echo ""
echo -e "${YELLOW}Deploy:${NC}"
echo "  cd ../../"
echo "  ./llmd-installer.sh -f custom-rtx-4000.yaml"
echo ""

echo -e "${GREEN}Example 17:${NC} High-performance L40S configuration"
echo -e "${YELLOW}Create custom-l40s-performance.yaml:${NC}"
echo "sampleApplication:"
echo "  decode:"
echo "    extraArgs:"
echo "      - \"--max-model-len\""
echo "      - \"32768\"                   # Larger sequence length"
echo "      - \"--gpu-memory-utilization\""
echo "      - \"0.95\"                    # Use 95% of GPU memory"
echo "      - \"--kv-cache-dtype\""
echo "      - \"fp8\"                     # Efficient cache"
echo ""

print_header "📈 Monitoring Configuration Examples"

echo -e "${GREEN}Example 18:${NC} Custom Grafana dashboard import"
echo -e "${YELLOW}Commands:${NC}"
echo "  # Copy dashboard to monitoring namespace"
echo "  kubectl create configmap custom-dashboard \\"
echo "    --from-file=my-dashboard.json \\"
echo "    -n llm-d-monitoring"
echo ""
echo "  # Restart Grafana to pick up new dashboard"
echo "  kubectl rollout restart deployment/prometheus-grafana -n llm-d-monitoring"
echo ""

echo -e "${GREEN}Example 19:${NC} Custom Prometheus alerts"
echo -e "${YELLOW}Create alert-rules.yaml:${NC}"
echo "groups:"
echo "  - name: llm-d-alerts"
echo "    rules:"
echo "      - alert: HighGPUMemoryUsage"
echo "        expr: vllm_gpu_cache_usage_perc > 90"
echo "        for: 5m"
echo "        annotations:"
echo "          summary: \"High GPU memory usage detected\""
echo ""

print_header "🌐 Production Deployment Examples"

echo -e "${GREEN}Example 20:${NC} Production deployment with custom domain"
echo -e "${YELLOW}Commands:${NC}"
echo "  # Deploy with production configuration"
echo "  ./deploy-with-monitoring.sh -g l40s -t \$HF_TOKEN"
echo ""
echo "  # Update Istio Gateway for custom domain"
echo "  kubectl patch gateway -n llm-d llm-d-gateway --type='merge' -p='{"
echo "    \"spec\": {"
echo "      \"servers\": [{"
echo "        \"hosts\": [\"your-domain.com\"],"
echo "        \"port\": {"
echo "          \"name\": \"http\","
echo "          \"number\": 80,"
echo "          \"protocol\": \"HTTP\""
echo "        }"
echo "      }]"
echo "    }"
echo "  }'"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}🎉 Ready to Deploy!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Choose an example above and run the commands."
echo "For help: ./deploy-with-monitoring.sh -h"
echo "" 