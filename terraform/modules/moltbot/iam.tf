# -----------------------------------------------------------------------------
# IAM ROLE FOR EC2 INSTANCE
# Allows SSM access and CloudWatch logging
# -----------------------------------------------------------------------------

resource "aws_iam_role" "moltbot" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach SSM managed policy for secure instance access
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.moltbot.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent policy for logging
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.moltbot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile
resource "aws_iam_instance_profile" "moltbot" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.moltbot.name

  tags = local.common_tags
}
