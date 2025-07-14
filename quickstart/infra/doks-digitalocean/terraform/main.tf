terraform {
  required_version = ">= 1.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.do_token
}

# Data source for latest Kubernetes version
data "digitalocean_kubernetes_versions" "latest" {
  version_prefix = var.kubernetes_version_prefix
}

# Get default VPC if using default
data "digitalocean_vpc" "default" {
  count = var.use_default_vpc ? 1 : 0
  name  = format("default-%s", var.cluster_region)
}

# Create custom VPC if requested
resource "digitalocean_vpc" "llm_d_vpc" {
  count       = var.use_default_vpc ? 0 : 1
  name        = var.vpc_name
  region      = var.cluster_region
  ip_range    = "172.16.0.0/16"
  description = "VPC for LLM-D GPU cluster"

  lifecycle {
    create_before_destroy = true
  }
}

# Create the Kubernetes cluster
resource "digitalocean_kubernetes_cluster" "llm_d_cluster" {
  name     = var.cluster_name
  region   = var.cluster_region
  version  = "1.33.1-do.1"
  vpc_uuid = var.use_default_vpc ? data.digitalocean_vpc.default[0].id : digitalocean_vpc.llm_d_vpc[0].id
  auto_upgrade = var.enable_auto_upgrade
  tags     = var.tags

  # CPU node pool (initial)
  node_pool {
    name       = var.cpu_node_pool_name
    size       = var.cpu_node_size
    node_count = var.cpu_node_count
    
    labels = merge({
      "worker-role" = "true"
      "cluster-component" = "cpu"
    }, var.additional_labels)

    tags = var.tags
  }

  # Maintenance window
  maintenance_policy {
    start_time = var.maintenance_time
    day        = var.maintenance_day
  }

  # Security settings
  surge_upgrade = true
  ha           = false

  lifecycle {
    ignore_changes = [
      version,
    ]
  }

  timeouts {
    create = "30m"
  }
}

# Create GPU node pool
resource "digitalocean_kubernetes_node_pool" "gpu_pool" {
  cluster_id = digitalocean_kubernetes_cluster.llm_d_cluster.id
  name       = var.gpu_node_pool_name
  size       = var.gpu_node_size
  node_count = var.gpu_node_count
  tags       = var.tags

  labels = merge({
    "worker-role" = "true"
    "cluster-component" = "gpu"
    "gpu-enabled" = "true"
    "doks.digitalocean.com/gpu-brand" = "nvidia"
    "pci-10de-present" = "true"
  }, var.additional_labels)

  # Taints for GPU nodes
  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NoSchedule"
  }

  timeouts {
    create = "30m"
  }

  depends_on = [
    digitalocean_kubernetes_cluster.llm_d_cluster
  ]
}

# Configure kubectl context
resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "doctl kubernetes cluster kubeconfig save ${var.cluster_name}"
  }

  depends_on = [
    digitalocean_kubernetes_cluster.llm_d_cluster
  ]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host  = digitalocean_kubernetes_cluster.llm_d_cluster.endpoint
  token = digitalocean_kubernetes_cluster.llm_d_cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(
    digitalocean_kubernetes_cluster.llm_d_cluster.kube_config[0].cluster_ca_certificate
  )
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    host  = digitalocean_kubernetes_cluster.llm_d_cluster.endpoint
    token = digitalocean_kubernetes_cluster.llm_d_cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(
      digitalocean_kubernetes_cluster.llm_d_cluster.kube_config[0].cluster_ca_certificate
    )
  }
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [
    digitalocean_kubernetes_cluster.llm_d_cluster,
    digitalocean_kubernetes_node_pool.gpu_pool
  ]
  create_duration = "120s"
}

# Create namespace for NVIDIA Device Plugin
resource "kubernetes_namespace" "nvidia_device_plugin" {
  metadata {
    name = var.nvidia_device_plugin_namespace
    labels = {
      "name" = var.nvidia_device_plugin_namespace
      "component" = "nvidia-device-plugin"
    }
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# Install NVIDIA Device Plugin
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvdp"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.nvidia_device_plugin_version
  namespace  = kubernetes_namespace.nvidia_device_plugin.metadata[0].name

  # Configure to only run on GPU nodes
  set {
    name  = "nodeSelector.doks\\.digitalocean\\.com/gpu-brand"
    value = "nvidia"
  }

  # Resource limits
  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  # Security context
  set {
    name  = "securityContext.allowPrivilegeEscalation"
    value = "false"
  }

  depends_on = [
    kubernetes_namespace.nvidia_device_plugin,
    digitalocean_kubernetes_node_pool.gpu_pool,
    time_sleep.wait_for_cluster
  ]

  timeout = 600
}

# Wait for NVIDIA Device Plugin to be ready
resource "time_sleep" "wait_for_device_plugin" {
  depends_on = [helm_release.nvidia_device_plugin]
  create_duration = "60s"
}

# Fix GPU node labels using local-exec
resource "null_resource" "fix_gpu_node_labels" {
  provisioner "local-exec" {
    command = <<-EOT
      # Wait a bit for nodes to be fully ready
      sleep 30
      
      # Get GPU nodes and add required labels
      kubectl get nodes -l doks.digitalocean.com/gpu-brand=nvidia -o name | while read node; do
        echo "Fixing labels for $node"
        kubectl label $node feature.node.kubernetes.io/pci-10de.present=true --overwrite
        kubectl label $node nvidia.com/gpu.present=true --overwrite
      done
      
      # Verify GPU resources
      echo "Verifying GPU resources..."
      kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | column -t
    EOT
  }

  depends_on = [
    helm_release.nvidia_device_plugin,
    time_sleep.wait_for_device_plugin
  ]
}

# Final verification
resource "null_resource" "cluster_verification" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Cluster Verification ==="
      echo "Cluster Name: ${var.cluster_name}"
      echo "Region: ${var.cluster_region}"
      echo "Kubernetes Version: ${data.digitalocean_kubernetes_versions.latest.latest_version}"
      echo ""
      echo "=== Node Status ==="
      kubectl get nodes -o wide
      echo ""
      echo "=== GPU Resources ==="
      kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | column -t
      echo ""
      echo "=== NVIDIA Device Plugin Pods ==="
      kubectl get pods -n ${var.nvidia_device_plugin_namespace}
      echo ""
      echo "=== Cluster is ready for LLM-D deployment! ==="
    EOT
  }

  depends_on = [
    null_resource.fix_gpu_node_labels
  ]
} 