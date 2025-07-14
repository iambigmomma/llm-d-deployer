# Cluster Information
output "cluster_id" {
  description = "ID of the created Kubernetes cluster"
  value       = digitalocean_kubernetes_cluster.llm_d_cluster.id
}

output "cluster_name" {
  description = "Name of the created Kubernetes cluster"
  value       = digitalocean_kubernetes_cluster.llm_d_cluster.name
}

output "cluster_region" {
  description = "Region where the cluster is deployed"
  value       = digitalocean_kubernetes_cluster.llm_d_cluster.region
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = digitalocean_kubernetes_cluster.llm_d_cluster.version
}

output "cluster_endpoint" {
  description = "Endpoint for the Kubernetes cluster"
  value       = digitalocean_kubernetes_cluster.llm_d_cluster.endpoint
  sensitive   = true
}

# VPC Information
output "vpc_id" {
  description = "ID of the VPC used by the cluster"
  value       = var.use_default_vpc ? data.digitalocean_vpc.default[0].id : digitalocean_vpc.llm_d_vpc[0].id
}

output "vpc_name" {
  description = "Name of the VPC used by the cluster"
  value       = var.use_default_vpc ? "Default VPC" : digitalocean_vpc.llm_d_vpc[0].name
}

# Node Pool Information
output "cpu_node_pool_id" {
  description = "ID of the CPU node pool"
  value       = digitalocean_kubernetes_cluster.llm_d_cluster.node_pool[0].id
}

output "gpu_node_pool_id" {
  description = "ID of the GPU node pool"
  value       = digitalocean_kubernetes_node_pool.gpu_pool.id
}

output "cpu_node_count" {
  description = "Number of CPU nodes"
  value       = var.cpu_node_count
}

output "gpu_node_count" {
  description = "Number of GPU nodes"
  value       = var.gpu_node_count
}

output "cpu_node_size" {
  description = "Size of CPU nodes"
  value       = var.cpu_node_size
}

output "gpu_node_size" {
  description = "Size of GPU nodes"
  value       = var.gpu_node_size
}

# NVIDIA Device Plugin Information
output "nvidia_device_plugin_namespace" {
  description = "Namespace of the NVIDIA Device Plugin"
  value       = kubernetes_namespace.nvidia_device_plugin.metadata[0].name
}

output "nvidia_device_plugin_version" {
  description = "Version of the installed NVIDIA Device Plugin"
  value       = var.nvidia_device_plugin_version
}

# Useful Commands
output "kubectl_config_command" {
  description = "Command to update kubectl configuration"
  value       = "doctl kubernetes cluster kubeconfig save ${digitalocean_kubernetes_cluster.llm_d_cluster.name}"
}

output "get_nodes_command" {
  description = "Command to get cluster nodes"
  value       = "kubectl get nodes -o wide"
}

output "get_gpu_resources_command" {
  description = "Command to check GPU resources"
  value       = "kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.status.allocatable.nvidia\\.com/gpu}{\"\\n\"}{end}' | column -t"
}

output "check_device_plugin_command" {
  description = "Command to check NVIDIA Device Plugin status"
  value       = "kubectl get pods -n ${kubernetes_namespace.nvidia_device_plugin.metadata[0].name}"
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for LLM-D deployment"
  value = <<-EOT
=== 🎉 Cluster Ready for LLM-D Deployment ===

📋 Cluster Information:
   Name: ${digitalocean_kubernetes_cluster.llm_d_cluster.name}
   Region: ${digitalocean_kubernetes_cluster.llm_d_cluster.region}
   Kubernetes Version: ${digitalocean_kubernetes_cluster.llm_d_cluster.version}
   VPC: ${var.use_default_vpc ? "Default VPC" : digitalocean_vpc.llm_d_vpc[0].name}

🖥️  Node Configuration:
   CPU Nodes: ${var.cpu_node_count}x ${var.cpu_node_size}
   GPU Nodes: ${var.gpu_node_count}x ${var.gpu_node_size}

🔧 Installed Components:
   ✅ NVIDIA Device Plugin ${var.nvidia_device_plugin_version}
   ✅ GPU Node Labels and Taints
   ✅ Kubernetes Access Configured

🚀 Next Steps:
   1. Verify cluster: kubectl get nodes
   2. Check GPU resources: kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | column -t
   3. Deploy LLM-D: cd ../.. && ./deploy-with-monitoring.sh -g rtx-6000-ada -t your_hf_token

💡 Helpful Commands:
   • Update kubectl config: doctl kubernetes cluster kubeconfig save ${digitalocean_kubernetes_cluster.llm_d_cluster.name}
   • Check Device Plugin: kubectl get pods -n ${kubernetes_namespace.nvidia_device_plugin.metadata[0].name}
   • Monitor GPU usage: kubectl describe nodes -l doks.digitalocean.com/gpu-brand=nvidia

🗑️  Cleanup (when done):
   • Destroy infrastructure: terraform destroy
   • Remove kubectl context: kubectl config delete-context do-${digitalocean_kubernetes_cluster.llm_d_cluster.region}-${digitalocean_kubernetes_cluster.llm_d_cluster.name}
  EOT
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    cpu_nodes_cost = "CPU nodes: ~$${var.cpu_node_count * 24}"
    gpu_nodes_cost = var.gpu_node_size == "gpu-4000adax1-48gb" ? "GPU nodes: ~$${var.gpu_node_count * 700}" : (
      var.gpu_node_size == "gpu-6000adax1-48gb" ? "GPU nodes: ~$${var.gpu_node_count * 1000}" : 
      "GPU nodes: ~$${var.gpu_node_count * 1400}"
    )
    total_estimate = var.gpu_node_size == "gpu-4000adax1-48gb" ? "Total: ~$${var.cpu_node_count * 24 + var.gpu_node_count * 700}" : (
      var.gpu_node_size == "gpu-6000adax1-48gb" ? "Total: ~$${var.cpu_node_count * 24 + var.gpu_node_count * 1000}" : 
      "Total: ~$${var.cpu_node_count * 24 + var.gpu_node_count * 1400}"
    )
    note = "Note: Actual costs may vary. Check DigitalOcean pricing for current rates."
  }
} 