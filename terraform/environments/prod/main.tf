provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "moltbot"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "moltbot" {
  source = "../../modules/moltbot"

  # Required: Your allowed SSH IP
  allowed_ssh_cidr = var.allowed_ssh_cidr

  # Naming
  project_name = "moltbot"
  environment  = "prod"

  # Network
  aws_region               = var.aws_region
  vpc_cidr                 = "10.100.0.0/16"
  public_subnet_cidr       = "10.100.1.0/24"
  availability_zone_suffix = "a"

  # EC2
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size
  root_volume_type = "gp3"

  # SSH Key
  create_ssh_key       = true
  ssh_private_key_path = "~/.ssh/moltbot_key.pem"
  ssh_public_key_path  = "~/.ssh/moltbot_key.pub"

  # User Data
  enable_user_data = true
  moltbot_user     = "clawd"
  install_node     = true
  install_moltbot  = true  # Installs CLI, user runs 'moltbot onboard' for config

  # Monitoring
  enable_detailed_monitoring = true
  enable_ssm                 = true

  # Additional Tags
  additional_tags = var.additional_tags
}

# Outputs from the module
output "instance_public_ip" {
  description = "Public IP address of the moltbot instance"
  value       = module.moltbot.instance_public_ip
}

output "ssh_connection_command" {
  description = "Command to SSH into the instance"
  value       = module.moltbot.ssh_connection_command
}

output "ssh_tunnel_command" {
  description = "Command to create SSH tunnel for gateway access"
  value       = module.moltbot.ssh_tunnel_command
}

output "gateway_local_url" {
  description = "URL to access gateway after SSH tunnel"
  value       = module.moltbot.gateway_local_url
}

output "security_reminder" {
  description = "Important security reminders"
  value       = module.moltbot.security_reminder
}
