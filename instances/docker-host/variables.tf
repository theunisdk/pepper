# Variables for OpenClaw Docker host instance

# -----------------------------------------------------------------------------
# AWS CONFIGURATION
# -----------------------------------------------------------------------------

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "noldor"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "af-south-1"
}

# -----------------------------------------------------------------------------
# NETWORK CONFIGURATION
# -----------------------------------------------------------------------------

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access (your IP/32)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.200.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.200.1.0/24"
}

# -----------------------------------------------------------------------------
# EC2 CONFIGURATION
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type (t3.medium for 3-5 bots, t3.large for 6-10)"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 50
}

# -----------------------------------------------------------------------------
# BOTS CONFIGURATION
# -----------------------------------------------------------------------------

variable "bots" {
  description = "List of bots to deploy on this Docker host"
  type = list(object({
    name = string
    port = number
  }))
  default = [
    { name = "pepper", port = 18789 },
    { name = "river", port = 18790 }
  ]
}

# -----------------------------------------------------------------------------
# SSH CONFIGURATION
# -----------------------------------------------------------------------------

variable "ssh_private_key_path" {
  description = "Path to save the SSH private key"
  type        = string
  default     = "~/.ssh/openclaw_docker_host_key.pem"
}

variable "ssh_public_key_path" {
  description = "Path to save the SSH public key"
  type        = string
  default     = "~/.ssh/openclaw_docker_host_key.pub"
}

# -----------------------------------------------------------------------------
# TAGS
# -----------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
