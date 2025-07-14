# DigitalOcean Token
variable "do_token" {
  description = "DigitalOcean Personal Access Token"
  type        = string
  sensitive   = true
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "llm-d-cluster"
}

variable "cluster_region" {
  description = "DigitalOcean region for the cluster"
  type        = string
  default     = "tor1"
  
  validation {
    condition = contains([
      "ams1", "ams2", "ams3", "blr1", "fra1", "lon1", "nyc1", "nyc2", "nyc3", 
      "sfo1", "sfo2", "sfo3", "sgp1", "tor1", "syd1"
    ], var.cluster_region)
    error_message = "Cluster region must be a valid DigitalOcean region."
  }
}

variable "kubernetes_version_prefix" {
  description = "Kubernetes version prefix (e.g., '1.33.' for latest 1.33.x)"
  type        = string
  default     = "1.33."
}

# VPC Configuration
variable "use_default_vpc" {
  description = "Use the default VPC instead of creating a custom one"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the custom VPC (only used if use_default_vpc is false)"
  type        = string
  default     = "llm-d-vpc"
}

# CPU Node Pool Configuration
variable "cpu_node_pool_name" {
  description = "Name of the CPU node pool"
  type        = string
  default     = "cpu-pool"
}

variable "cpu_node_size" {
  description = "Size of CPU nodes"
  type        = string
  default     = "s-2vcpu-4gb"
  
  validation {
    condition = can(regex("^(s-|c-|g-|so-|m-)", var.cpu_node_size))
    error_message = "CPU node size must be a valid DigitalOcean droplet size."
  }
}

variable "cpu_node_count" {
  description = "Number of CPU nodes"
  type        = number
  default     = 1  # Changed to 1 to match typical deployment
  
  validation {
    condition     = var.cpu_node_count >= 1 && var.cpu_node_count <= 100
    error_message = "CPU node count must be between 1 and 100."
  }
}

# GPU Node Pool Configuration
variable "gpu_node_pool_name" {
  description = "Name of the GPU node pool"
  type        = string
  default     = "gpu-pool"
}

variable "gpu_node_size" {
  description = "Size of GPU nodes"
  type        = string
  default     = "gpu-6000adax1-48gb"
  
  validation {
    condition = contains([
      "gpu-4000adax1-20gb",  # RTX 4000 Ada
      "gpu-6000adax1-48gb",  # RTX 6000 Ada
      "gpu-l40sx1-48gb"      # L40S
    ], var.gpu_node_size)
    error_message = "GPU node size must be one of: gpu-4000adax1-20gb, gpu-6000adax1-48gb, gpu-l40sx1-48gb."
  }
}

variable "gpu_node_count" {
  description = "Number of GPU nodes"
  type        = number
  default     = 1  # Changed to 1 to match typical deployment
  
  validation {
    condition     = var.gpu_node_count >= 1 && var.gpu_node_count <= 10
    error_message = "GPU node count must be between 1 and 10."
  }
}

# NVIDIA Device Plugin Configuration
variable "nvidia_device_plugin_namespace" {
  description = "Namespace for NVIDIA Device Plugin"
  type        = string
  default     = "nvidia-device-plugin"
}

variable "nvidia_device_plugin_version" {
  description = "Version of NVIDIA Device Plugin to install"
  type        = string
  default     = "v0.14.5"
}

# Tags and Labels
variable "tags" {
  description = "Tags to apply to all resources"
  type        = list(string)
  default     = ["llm-d", "gpu-cluster", "kubernetes"]
}

variable "additional_labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}

# Environment and Project Information
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "llm-d"
}

# Advanced Configuration
variable "enable_monitoring" {
  description = "Enable DigitalOcean monitoring for the cluster"
  type        = bool
  default     = true
}

variable "enable_auto_upgrade" {
  description = "Enable automatic upgrades for the cluster"
  type        = bool
  default     = false
}

variable "maintenance_day" {
  description = "Day of the week for maintenance (sunday, monday, etc.)"
  type        = string
  default     = "sunday"
  
  validation {
    condition = contains([
      "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"
    ], var.maintenance_day)
    error_message = "Maintenance day must be a valid day of the week."
  }
}

variable "maintenance_time" {
  description = "Time of day for maintenance (HH:MM format)"
  type        = string
  default     = "04:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_time))
    error_message = "Maintenance time must be in HH:MM format (24-hour)."
  }
} 