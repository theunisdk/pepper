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

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "openclaw"
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
  description = "AWS region for deployment (choose one close to you for latency)"
  type        = string
  default     = "af-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.100.1.0/24"
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
  description = "EC2 instance type (t3.small recommended for light usage, t3.medium for production)"
  type        = string
  default     = "t3.small"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3a.small", "t3.medium", "t3a.medium"], var.instance_type)
    error_message = "Instance type must be one of: t3.micro, t3.small, t3a.small, t3.medium, t3a.medium."
  }
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB (20-50 recommended)"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 20 and 100 GB."
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
  description = "Path to save the generated SSH public key (only if create_ssh_key is true)"
  type        = string
  default     = "~/.ssh/openclaw_key.pub"
}

variable "ssh_private_key_path" {
  description = "Path to save the generated SSH private key (only if create_ssh_key is true)"
  type        = string
  default     = "~/.ssh/openclaw_key.pem"
}

# -----------------------------------------------------------------------------
# USER DATA / OS HARDENING
# -----------------------------------------------------------------------------

variable "enable_user_data" {
  description = "Whether to include user_data script for initial OS hardening and setup"
  type        = bool
  default     = true
}

variable "openclaw_user" {
  description = "Non-root user to create for running OpenClaw"
  type        = string
  default     = "clawd"
}

variable "install_node" {
  description = "Whether to install Node.js 22+ via user_data"
  type        = bool
  default     = true
}

variable "install_openclaw" {
  description = "Whether to install OpenClaw via user_data (requires manual configuration after)"
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
