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
  value       = aws_security_group.openclaw.id
}

# -----------------------------------------------------------------------------
# EC2 OUTPUTS
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.openclaw.id
}

output "instance_public_ip" {
  description = "Elastic IP address of the instance"
  value       = aws_eip.openclaw.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.openclaw.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_eip.openclaw.public_dns
}

# -----------------------------------------------------------------------------
# SSH CONNECTION INFO
# -----------------------------------------------------------------------------

output "ssh_private_key_path" {
  description = "Path to the SSH private key (if created)"
  value       = var.create_ssh_key ? pathexpand(var.ssh_private_key_path) : "Using existing key: ${var.existing_key_name}"
}

output "ssh_connection_command" {
  description = "Command to SSH into the instance"
  value       = var.create_ssh_key ? "ssh -i ${pathexpand(var.ssh_private_key_path)} ubuntu@${aws_eip.openclaw.public_ip}" : "ssh -i <your-key.pem> ubuntu@${aws_eip.openclaw.public_ip}"
}

output "ssh_tunnel_command" {
  description = "Command to create SSH tunnel for gateway access (DO NOT expose port 18789 publicly)"
  value       = var.create_ssh_key ? "ssh -i ${pathexpand(var.ssh_private_key_path)} -L 18789:127.0.0.1:18789 ubuntu@${aws_eip.openclaw.public_ip} -N" : "ssh -i <your-key.pem> -L 18789:127.0.0.1:18789 ubuntu@${aws_eip.openclaw.public_ip} -N"
}

output "gateway_local_url" {
  description = "URL to access gateway after establishing SSH tunnel"
  value       = "http://127.0.0.1:18789"
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
# SECURITY REMINDERS
# -----------------------------------------------------------------------------

output "security_reminder" {
  description = "Important security information"
  value       = <<-EOT
    SECURITY REMINDERS:
    1. NEVER expose port 18789 to the internet - use SSH tunnel
    2. Gateway should bind to 127.0.0.1 only
    3. SSH is restricted to: ${var.allowed_ssh_cidr}
    4. Use the clawd user for OpenClaw operations, not ubuntu/root
    5. Configure OpenClaw API keys with minimal permissions
  EOT
}
