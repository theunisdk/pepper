variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (your IP)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to save SSH private key"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to save SSH public key"
  type        = string
}

variable "moltbot_user" {
  description = "Non-root user for running moltbot"
  type        = string
}

variable "gateway_port" {
  description = "Moltbot gateway port"
  type        = number
  default     = 18789
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
