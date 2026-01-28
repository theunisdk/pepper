# -----------------------------------------------------------------------------
# SSH KEY PAIR
# Option 1: Generate new key pair via Terraform
# Option 2: Use existing key pair
# -----------------------------------------------------------------------------

# Generate TLS private key if creating new key pair
resource "tls_private_key" "moltbot" {
  count     = var.create_ssh_key ? 1 : 0
  algorithm = "ED25519"
}

# Create AWS key pair from generated key
resource "aws_key_pair" "moltbot" {
  count      = var.create_ssh_key ? 1 : 0
  key_name   = "${local.name_prefix}-key"
  public_key = tls_private_key.moltbot[0].public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-key"
  })
}

# Save private key locally (with secure permissions)
resource "local_sensitive_file" "private_key" {
  count           = var.create_ssh_key ? 1 : 0
  content         = tls_private_key.moltbot[0].private_key_openssh
  filename        = pathexpand(var.ssh_private_key_path)
  file_permission = "0400"
}

# Save public key locally
resource "local_file" "public_key" {
  count           = var.create_ssh_key ? 1 : 0
  content         = tls_private_key.moltbot[0].public_key_openssh
  filename        = pathexpand(var.ssh_public_key_path)
  file_permission = "0644"
}

# -----------------------------------------------------------------------------
# EC2 INSTANCE
# Ubuntu 22.04 LTS with security hardening
# -----------------------------------------------------------------------------

resource "aws_instance" "moltbot" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.create_ssh_key ? aws_key_pair.moltbot[0].key_name : var.existing_key_name
  vpc_security_group_ids      = [aws_security_group.moltbot.id]
  subnet_id                   = aws_subnet.public.id
  iam_instance_profile        = aws_iam_instance_profile.moltbot.name
  monitoring                  = var.enable_detailed_monitoring
  associate_public_ip_address = true

  # Root volume configuration
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = true
    delete_on_termination = true
  }

  # Metadata options for enhanced security (IMDSv2 required)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # User data for initial setup and hardening
  user_data = var.enable_user_data ? templatefile("${path.module}/user_data/init.sh.tftpl", {
    moltbot_user    = var.moltbot_user
    install_node    = var.install_node
    install_moltbot = var.install_moltbot
    gateway_port    = local.gateway_port
  }) : null

  user_data_replace_on_change = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-instance"
  })

  volume_tags = local.common_tags

  lifecycle {
    ignore_changes = [
      ami, # Don't recreate on new AMI releases
    ]
  }
}

# -----------------------------------------------------------------------------
# ELASTIC IP (provides stable public IP)
# -----------------------------------------------------------------------------

resource "aws_eip" "moltbot" {
  instance = aws_instance.moltbot.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eip"
  })

  depends_on = [aws_internet_gateway.main]
}
