# -----------------------------------------------------------------------------
# SECURITY GROUP
# Minimal ingress - SSH only from specified IP
# All container ports bound to 127.0.0.1 (access via SSH tunnel)
# -----------------------------------------------------------------------------

resource "aws_security_group" "docker_host" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for OpenClaw Docker host - SSH only from trusted IP"
  vpc_id      = aws_vpc.main.id

  # SSH access from specific IP only
  ingress {
    description = "SSH from trusted IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # NOTE: Container ports (18789-18799) are NOT opened
  # All containers bind to 127.0.0.1, access via SSH tunnel only

  # Allow all outbound traffic (for updates, Docker pulls, API calls)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# NETWORK ACL
# Additional layer of security at subnet level
# -----------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id]

  # Allow inbound SSH from trusted IP
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.allowed_ssh_cidr
    from_port  = 22
    to_port    = 22
  }

  # Allow inbound ephemeral ports (for return traffic from outbound connections)
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow inbound UDP ephemeral ports (DNS responses, etc.)
  ingress {
    protocol   = "udp"
    rule_no    = 210
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny all other inbound traffic (explicit)
  ingress {
    protocol   = "-1"
    rule_no    = 32766
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nacl"
  })
}
