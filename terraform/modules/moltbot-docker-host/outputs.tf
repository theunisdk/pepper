# -----------------------------------------------------------------------------
# NETWORK OUTPUTS
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the dedicated VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.docker_host.id
}

# -----------------------------------------------------------------------------
# EC2 OUTPUTS
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 Docker host instance"
  value       = aws_instance.docker_host.id
}

output "instance_public_ip" {
  description = "Elastic IP address of the Docker host"
  value       = aws_eip.docker_host.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the Docker host"
  value       = aws_instance.docker_host.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the Docker host"
  value       = aws_eip.docker_host.public_dns
}

# -----------------------------------------------------------------------------
# SSH CONNECTION INFO
# -----------------------------------------------------------------------------

output "ssh_private_key_path" {
  description = "Path to the SSH private key (if created)"
  value       = var.create_ssh_key ? pathexpand(var.ssh_private_key_path) : "Using existing key: ${var.existing_key_name}"
}

output "ssh_connection_command" {
  description = "Command to SSH into the Docker host"
  value       = var.create_ssh_key ? "ssh -i ${pathexpand(var.ssh_private_key_path)} ubuntu@${aws_eip.docker_host.public_ip}" : "ssh -i <your-key.pem> ubuntu@${aws_eip.docker_host.public_ip}"
}

# -----------------------------------------------------------------------------
# BOT-SPECIFIC OUTPUTS
# -----------------------------------------------------------------------------

output "bots" {
  description = "Configuration for each deployed bot"
  value = {
    for bot in var.bots : bot.name => {
      name           = bot.name
      port           = bot.port
      tunnel_command = var.create_ssh_key ? "ssh -i ${pathexpand(var.ssh_private_key_path)} -L ${bot.port}:127.0.0.1:${bot.port} ubuntu@${aws_eip.docker_host.public_ip} -N" : "ssh -i <your-key.pem> -L ${bot.port}:127.0.0.1:${bot.port} ubuntu@${aws_eip.docker_host.public_ip} -N"
      local_url      = "http://127.0.0.1:${bot.port}"
    }
  }
}

output "bot_tunnel_commands" {
  description = "SSH tunnel commands for each bot"
  value = {
    for bot in var.bots : bot.name => var.create_ssh_key ? "ssh -i ${pathexpand(var.ssh_private_key_path)} -L ${bot.port}:127.0.0.1:${bot.port} ubuntu@${aws_eip.docker_host.public_ip} -N" : "ssh -i <your-key.pem> -L ${bot.port}:127.0.0.1:${bot.port} ubuntu@${aws_eip.docker_host.public_ip} -N"
  }
}

# -----------------------------------------------------------------------------
# AMI INFO
# -----------------------------------------------------------------------------

output "ami_id" {
  description = "ID of the Ubuntu AMI used"
  value       = data.aws_ami.ubuntu.id
}

output "ami_name" {
  description = "Name of the Ubuntu AMI used"
  value       = data.aws_ami.ubuntu.name
}

# -----------------------------------------------------------------------------
# DOCKER MANAGEMENT COMMANDS
# -----------------------------------------------------------------------------

output "docker_commands" {
  description = "Useful Docker commands for managing the host"
  value       = <<-EOT
    DOCKER HOST MANAGEMENT:

    SSH to host:
      ssh -i ${var.create_ssh_key ? pathexpand(var.ssh_private_key_path) : "<your-key.pem>"} ubuntu@${aws_eip.docker_host.public_ip}

    View all containers:
      docker compose -f /opt/moltbot/docker-compose.yml ps

    View logs (all bots):
      docker compose -f /opt/moltbot/docker-compose.yml logs -f

    View logs (specific bot):
      docker compose -f /opt/moltbot/docker-compose.yml logs -f <bot-name>

    Restart a bot:
      docker compose -f /opt/moltbot/docker-compose.yml restart <bot-name>

    Shell into a bot container:
      docker compose -f /opt/moltbot/docker-compose.yml exec <bot-name> bash

    Resource usage:
      docker stats
  EOT
}

# -----------------------------------------------------------------------------
# SECURITY REMINDERS
# -----------------------------------------------------------------------------

output "security_reminder" {
  description = "Important security information"
  value       = <<-EOT
    SECURITY REMINDERS:
    1. All container ports (18789-18799) are bound to 127.0.0.1 - use SSH tunnel
    2. SSH is restricted to: ${var.allowed_ssh_cidr}
    3. Each bot has isolated Docker volumes for data separation
    4. Use 'moltbot onboard' inside each container for initial setup
    5. Configure API keys with minimal permissions
  EOT
}
