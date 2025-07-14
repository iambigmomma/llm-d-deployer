# DigitalOcean GPU Kubernetes Cluster with Terraform

This directory contains Terraform configurations to create a complete DigitalOcean Kubernetes (DOKS) cluster with GPU support for LLM-D deployment.

## 🚀 Quick Start

### Option 1: Using the Wrapper Script (Recommended)

```bash
# Navigate to the project directory
cd quickstart/infra/doks-digitalocean

# Set your DigitalOcean token
export TF_VAR_do_token=your_digitalocean_token_here

# Create cluster with default settings (RTX 6000 Ada)
./setup-gpu-cluster-terraform.sh

# Create cluster with specific GPU type and region
./setup-gpu-cluster-terraform.sh -g l40s -r nyc1 -y

# Show what would be created (dry run)
./setup-gpu-cluster-terraform.sh -d

# Destroy the infrastructure
./setup-gpu-cluster-terraform.sh --destroy
```

### Option 2: Direct Terraform Usage

```bash
# Navigate to terraform directory
cd quickstart/infra/doks-digitalocean/terraform

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Destroy when done
terraform destroy
```

## 📋 Prerequisites

1. **Tools Required:**

   - [Terraform](https://www.terraform.io/downloads.html) >= 1.0
   - [doctl](https://docs.digitalocean.com/reference/doctl/) CLI
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
   - [jq](https://stedolan.github.io/jq/) (for JSON processing)

2. **DigitalOcean Setup:**

   - DigitalOcean account with GPU quota enabled
   - [Personal Access Token](https://cloud.digitalocean.com/account/api/tokens)
   - Authenticated doctl: `doctl auth init`

3. **Environment Variables:**
   ```bash
   export TF_VAR_do_token=your_digitalocean_token
   # OR
   export DO_TOKEN=your_digitalocean_token
   ```

## ⚙️ Configuration

### GPU Type Options

| GPU Type     | DigitalOcean Size  | Monthly Cost\* | Use Case                |
| ------------ | ------------------ | -------------- | ----------------------- |
| rtx-4000-ada | gpu-4000adax1-48gb | ~$700          | Small models (7B-13B)   |
| rtx-6000-ada | gpu-6000adax1-48gb | ~$1000         | Medium models (13B-34B) |
| l40s         | gpu-l40sx1-48gb    | ~$1400         | Large models (70B+)     |

\*Costs are estimates and may vary

### Region Options

Available DigitalOcean regions with GPU support:

- `nyc1`, `nyc2`, `nyc3` - New York
- `ams1`, `ams2`, `ams3` - Amsterdam
- `sfo1`, `sfo2`, `sfo3` - San Francisco
- `sgp1` - Singapore
- `lon1` - London
- `fra1` - Frankfurt
- `tor1` - Toronto
- `blr1` - Bangalore
- `syd1` - Sydney

### Customization

Edit `terraform.tfvars` to customize your deployment:

```hcl
cluster_name   = "my-llm-cluster"
cluster_region = "nyc1"
gpu_node_size  = "gpu-l40sx1-48gb"
gpu_node_count = 1
cpu_node_count = 2
use_default_vpc = true
```

## 📁 File Structure

```
terraform/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── terraform.tfvars.example   # Example variables file
├── README.md                  # This file
├── .gitignore                 # Git ignore patterns
└── .terraform/                # Terraform working directory (auto-created)
```

## 🔧 What Gets Created

The Terraform configuration creates:

### Infrastructure

- **Kubernetes Cluster**: DOKS cluster with latest Kubernetes version
- **CPU Node Pool**: 2x s-2vcpu-4gb nodes (default)
- **GPU Node Pool**: 2x GPU nodes with selected type
- **VPC**: Default or custom VPC based on configuration

### GPU Support

- **NVIDIA Device Plugin**: Automatically installed via Helm
- **Node Labels**: Proper GPU node labeling for scheduling
- **Taints**: GPU nodes tainted for dedicated workloads

### Networking

- **Load Balancer**: Ready for LLM-D gateway exposure
- **Security Groups**: Properly configured for Kubernetes

## 🚀 Next Steps After Deployment

1. **Verify Cluster:**

   ```bash
   kubectl get nodes
   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | column -t
   ```

2. **Deploy LLM-D:**

   ```bash
   cd ../..
   ./deploy-with-monitoring.sh -g rtx-6000-ada -t your_hf_token
   ```

3. **Monitor Resources:**
   ```bash
   kubectl get pods -n nvidia-device-plugin
   kubectl describe nodes -l doks.digitalocean.com/gpu-brand=nvidia
   ```

## 🔄 Infrastructure as Code Benefits

- **Version Control**: All infrastructure changes are tracked
- **Reproducibility**: Identical deployments across environments
- **State Management**: Terraform tracks resource state
- **Planning**: Preview changes before applying
- **Rollback**: Easy destruction and recreation

## 🛡️ Security Considerations

- **Token Storage**: Store DO token in environment variables, not in code
- **State Files**: Keep terraform.tfstate secure (contains sensitive data)
- **VPC**: Consider using custom VPC for production deployments
- **RBAC**: Default cluster has basic RBAC enabled

## 🗑️ Cleanup

### Complete Destruction

```bash
# Using wrapper script
./setup-gpu-cluster-terraform.sh --destroy

# Using Terraform directly
cd terraform/
terraform destroy
```

### Partial Cleanup

```bash
# Remove specific resources
terraform destroy -target=digitalocean_kubernetes_node_pool.gpu_pool
```

## 🔍 Troubleshooting

### Common Issues

1. **Token Authentication**

   ```bash
   # Check doctl authentication
   doctl account get

   # Re-authenticate if needed
   doctl auth init
   ```

2. **Resource Limits**

   ```bash
   # Check DigitalOcean limits
   doctl projects resources list
   ```

3. **Terraform State Issues**

   ```bash
   # Refresh state
   terraform refresh

   # Import existing resources if needed
   terraform import digitalocean_kubernetes_cluster.llm_d_cluster CLUSTER_ID
   ```

4. **GPU Node Issues**
   ```bash
   # Check NVIDIA Device Plugin
   kubectl get pods -n nvidia-device-plugin
   kubectl logs -n nvidia-device-plugin -l app.kubernetes.io/name=nvidia-device-plugin
   ```

### Debug Commands

```bash
# Terraform debugging
export TF_LOG=DEBUG
terraform plan

# Kubernetes debugging
kubectl describe nodes
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

## 📚 Additional Resources

- [Terraform DigitalOcean Provider](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs)
- [DigitalOcean Kubernetes Documentation](https://docs.digitalocean.com/products/kubernetes/)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [LLM-D Documentation](https://github.com/DigitalOcean/llm-d)

## 🤝 Contributing

When modifying the Terraform configuration:

1. Test changes with `terraform plan`
2. Validate syntax with `terraform validate`
3. Format code with `terraform fmt`
4. Update this README if adding new features
5. Ensure sensitive data is not committed

## 📄 License

This Terraform configuration is part of the LLM-D project and follows the same license terms.
