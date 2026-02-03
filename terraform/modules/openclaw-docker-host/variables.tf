# -----------------------------------------------------------------------------
# REQUIRED VARIABLES
# -----------------------------------------------------------------------------

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access (e.g., '203.0.113.50/32' for single IP). NEVER use 0.0.0.0/0"
  type        = string

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "SSH access from 0.0.0.0/0 is not allowed for security reasons. Specify your IP with /32 suffix."
  }

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "The allowed_ssh_cidr must be a valid CIDR notation (e.g., '203.0.113.50/32')."
  }
}

variable "bots" {
  description = "List of bot configurations to deploy on this Docker host"
  type = list(object({
    name = string
    port = number
  }))

  validation {
    condition     = length(var.bots) > 0 && length(var.bots) <= 10
    error_message = "Must deploy between 1 and 10 bots."
  }

  validation {
    condition     = alltrue([for bot in var.bots : bot.port >= 18789 && bot.port <= 18799])
    error_message = "Bot ports must be between 18789 and 18799."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "openclaw-docker"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "prod"
}

# -----------------------------------------------------------------------------
# NETWORK CONFIGURATION
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "af-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC"
  type        = string
  default     = "10.200.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.200.1.0/24"
}

variable "availability_zone_suffix" {
  description = "Availability zone suffix (a, b, c, etc.)"
  type        = string
  default     = "a"
}

# -----------------------------------------------------------------------------
# EC2 CONFIGURATION
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type (t3.medium for 3-5 bots, t3.large for 6-10 bots)"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = contains(["t3.medium", "t3a.medium", "t3.large", "t3a.large", "t3.xlarge"], var.instance_type)
    error_message = "Instance type must be t3.medium or larger for Docker host."
  }
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB (50+ recommended for Docker host)"
  type        = number
  default     = 50

  validation {
    condition     = var.root_volume_size >= 30 && var.root_volume_size <= 200
    error_message = "Root volume size must be between 30 and 200 GB."
  }
}

variable "root_volume_type" {
  description = "EBS volume type for root volume"
  type        = string
  default     = "gp3"
}

# -----------------------------------------------------------------------------
# SSH KEY CONFIGURATION
# -----------------------------------------------------------------------------

variable "create_ssh_key" {
  description = "Whether to create a new SSH key pair via Terraform"
  type        = bool
  default     = true
}

variable "existing_key_name" {
  description = "Name of existing EC2 key pair to use (only if create_ssh_key is false)"
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to save the generated SSH public key"
  type        = string
  default     = "~/.ssh/openclaw_docker_host_key.pub"
}

variable "ssh_private_key_path" {
  description = "Path to save the generated SSH private key"
  type        = string
  default     = "~/.ssh/openclaw_docker_host_key.pem"
}

# -----------------------------------------------------------------------------
# DOCKER CONFIGURATION
# -----------------------------------------------------------------------------

variable "docker_image" {
  description = "Docker image to use for OpenClaw containers"
  type        = string
  default     = "openclaw-local"
}

variable "auto_start_containers" {
  description = "Whether to automatically start containers after provisioning"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# MONITORING AND LOGGING
# -----------------------------------------------------------------------------

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for the EC2 instance"
  type        = bool
  default     = true
}

variable "enable_ssm" {
  description = "Enable AWS Systems Manager for secure instance access"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# TAGGING
# -----------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
