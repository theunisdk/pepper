# Terraform configuration for moltbot Docker host
# Runs multiple moltbot instances as Docker containers on a single EC2

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "moltbot-docker-host"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "docker_host" {
  source = "../../terraform/modules/moltbot-docker-host"

  # Required: Your allowed SSH IP
  allowed_ssh_cidr = var.allowed_ssh_cidr

  # Bots to deploy
  bots = var.bots

  # Naming
  project_name = "moltbot-docker"
  environment  = "prod"

  # Network
  aws_region               = var.aws_region
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidr       = var.public_subnet_cidr
  availability_zone_suffix = "a"

  # EC2 (larger instance for Docker)
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size
  root_volume_type = "gp3"

  # SSH Key
  create_ssh_key       = true
  ssh_private_key_path = var.ssh_private_key_path
  ssh_public_key_path  = var.ssh_public_key_path

  # Docker settings
  docker_image          = "moltbot-local"
  auto_start_containers = false  # Start manually after onboarding

  # Monitoring
  enable_detailed_monitoring = true
  enable_ssm                 = true

  # Additional Tags
  additional_tags = var.additional_tags
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------

output "instance_public_ip" {
  description = "Public IP address of the Docker host"
  value       = module.docker_host.instance_public_ip
}

output "ssh_connection_command" {
  description = "Command to SSH into the Docker host"
  value       = module.docker_host.ssh_connection_command
}

output "bots" {
  description = "Configuration for each deployed bot"
  value       = module.docker_host.bots
}

output "bot_tunnel_commands" {
  description = "SSH tunnel commands for each bot"
  value       = module.docker_host.bot_tunnel_commands
}

output "docker_commands" {
  description = "Useful Docker management commands"
  value       = module.docker_host.docker_commands
}

output "security_reminder" {
  description = "Security best practices reminder"
  value       = module.docker_host.security_reminder
}
