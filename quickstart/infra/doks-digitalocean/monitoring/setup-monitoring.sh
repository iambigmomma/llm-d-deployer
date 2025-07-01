#!/bin/bash

# LLM-D Monitoring Setup Script for DigitalOcean Kubernetes
# Installs Prometheus, Grafana, and custom dashboards

set -euo pipefail

echo "🚀 Setting up LLM-D Monitoring Stack..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="llm-d-monitoring"
PROMETHEUS_CHART="prometheus-community/kube-prometheus-stack"
CHART_VERSION="62.3.1"

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
    
    print_success "Prerequisites check passed"
}

# Add Helm repositories
setup_helm_repos() {
    print_status "Setting up Helm repositories..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    print_success "Helm repositories configured"
}

# Create namespace
create_namespace() {
    print_status "Creating namespace: ${NAMESPACE}"
    
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_warning "Namespace ${NAMESPACE} already exists"
    else
        kubectl create namespace ${NAMESPACE}
        print_success "Namespace ${NAMESPACE} created"
    fi
}

# Install Prometheus Stack
install_prometheus_stack() {
    print_status "Installing Prometheus Stack..."
    
    # Create values file for prometheus stack
    cat <<EOF > prometheus-values.yaml
# Prometheus Stack Configuration for LLM-D
global:
  imageRegistry: ""

## Configure prometheus
prometheus:
  prometheusSpec:
    retention: 7d
    retentionSize: 10GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: do-block-storage
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
    
    # ServiceMonitor selector
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    
    # Additional scrape configs for LLM-D
    additionalScrapeConfigs:
      - job_name: 'llm-d-modelservice'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names: ["llm-d"]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: (\d+)
            target_label: __meta_kubernetes_pod_container_port_number
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: \$1:\$2
            target_label: __address__

## Configure Grafana
grafana:
  
  persistence:
    enabled: true
    storageClassName: do-block-storage
    size: 5Gi
  
  
  # Grafana configuration
  grafana.ini:
    server:
      root_url: http://localhost:3000
    # Remove security section with admin_password
    # security:
    #   admin_user: admin
    #   admin_password: admin
    
  # Remove custom datasources to avoid conflicts with default ones
  # datasources:
  #   datasources.yaml:
  #     apiVersion: 1
  #     datasources:
  #       - name: Prometheus
  #         type: prometheus
  #         url: http://prometheus-kube-prometheus-prometheus:9090
  #         access: proxy
  #         isDefault: true
  
  # Import dashboards
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 1860
        revision: 29
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6336
        revision: 1
        datasource: Prometheus

## Configure AlertManager
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: do-block-storage
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

## Node Exporter
nodeExporter:
  enabled: true

## Kube State Metrics
kubeStateMetrics:
  enabled: true

## Configure ServiceMonitor for VLLM
additionalServiceMonitors:
  - name: vllm-metrics
    selector:
      matchLabels:
        app: llm-d-modelservice
    endpoints:
      - port: metrics
        interval: 15s
        path: /metrics
EOF

    # Install or upgrade
    helm upgrade --install prometheus ${PROMETHEUS_CHART} \
        --namespace ${NAMESPACE} \
        --version ${CHART_VERSION} \
        --values prometheus-values.yaml \
        --wait --timeout=600s
    
    print_success "Prometheus Stack installed successfully"
}

# Create LLM-D specific ServiceMonitor
create_llm_d_service_monitor() {
    print_status "Creating LLM-D ServiceMonitor..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: llm-d-modelservice
  namespace: ${NAMESPACE}
  labels:
    app: llm-d-monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: modelservice
  namespaceSelector:
    matchNames:
      - llm-d
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
      honorLabels: true
EOF
    
    print_success "LLM-D ServiceMonitor created"
}

# Import LLM-D Dashboard
import_llm_d_dashboard() {
    print_status "Importing LLM-D Dashboard..."
    
    # Wait for Grafana to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n ${NAMESPACE} --timeout=300s
    
    # Create ConfigMap with dashboard (will be picked up by sidecar)
    if [[ -f "llm-d-dashboard.json" ]]; then
        # Delete existing ConfigMap if it exists
        kubectl delete configmap llm-d-dashboard -n ${NAMESPACE} --ignore-not-found=true
        
        # Create new ConfigMap with proper structure for Grafana Sidecar
        kubectl create configmap llm-d-dashboard \
            --from-file=llm-d-dashboard.json \
            -n ${NAMESPACE}
        
        # Add required labels and annotations for Grafana Sidecar
        kubectl label configmap llm-d-dashboard grafana_dashboard=1 -n ${NAMESPACE} --overwrite
        kubectl annotate configmap llm-d-dashboard grafana_folder="LLM-D" -n ${NAMESPACE} --overwrite
        
        # Force Grafana to reload dashboards by restarting the pod
        kubectl rollout restart deployment prometheus-grafana -n ${NAMESPACE}
        kubectl rollout status deployment prometheus-grafana -n ${NAMESPACE} --timeout=300s
        
        print_success "LLM-D Dashboard imported and Grafana restarted"
    else
        print_warning "llm-d-dashboard.json not found, skipping dashboard import"
    fi
}

# Get access information
show_access_info() {
    print_status "Getting access information..."
    
    # Wait for services to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n ${NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n ${NAMESPACE} --timeout=300s
    
    # Get Grafana admin password
    GRAFANA_PASSWORD=$(kubectl get secret prometheus-grafana -n ${NAMESPACE} -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo "Unable to retrieve")
    
    echo ""
    echo "=================================="
    echo "🎉 Monitoring Stack Ready!"
    echo "=================================="
    echo ""
    echo "📊 Prometheus:"
    echo "  Port-forward: kubectl port-forward -n ${NAMESPACE} svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "  URL: http://localhost:9090"
    echo ""
    echo "📈 Grafana:"
    echo "  Port-forward: kubectl port-forward -n ${NAMESPACE} svc/prometheus-grafana 3000:80"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: ${GRAFANA_PASSWORD}"
    echo ""
    echo "💡 To get Grafana password later:"
    echo "  kubectl get secret prometheus-grafana -n ${NAMESPACE} -o jsonpath=\"{.data.admin-password}\" | base64 -d"
    echo ""
    echo "🚨 AlertManager:"
    echo "  Port-forward: kubectl port-forward -n ${NAMESPACE} svc/prometheus-kube-prometheus-alertmanager 9093:9093"
    echo "  URL: http://localhost:9093"
    echo ""
    echo "💡 Quick Commands:"
    echo "  # Access Grafana"
    echo "  kubectl port-forward -n ${NAMESPACE} svc/prometheus-grafana 3000:80"
    echo ""
    echo "  # Access Prometheus"
    echo "  kubectl port-forward -n ${NAMESPACE} svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo ""
    echo "  # Check monitoring pods"
    echo "  kubectl get pods -n ${NAMESPACE}"
    echo ""
    echo "  # View LLM-D metrics"
    echo "  kubectl get servicemonitor -n ${NAMESPACE}"
    echo ""
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -f prometheus-values.yaml
}

# Main execution
main() {
    echo "🚀 LLM-D Monitoring Setup"
    echo "=========================="
    echo ""
    
    check_prerequisites
    setup_helm_repos
    create_namespace
    install_prometheus_stack
    create_llm_d_service_monitor
    
    # Check if dashboard file exists
    if [[ -f "llm-d-dashboard.json" ]]; then
        import_llm_d_dashboard
    else
        print_warning "llm-d-dashboard.json not found, skipping dashboard import"
    fi
    
    show_access_info
    cleanup
    
    print_success "🎉 Monitoring setup completed successfully!"
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@" 