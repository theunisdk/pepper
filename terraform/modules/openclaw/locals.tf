locals {
  name_prefix = "${var.project_name}-${var.environment}"
  az          = "${var.aws_region}${var.availability_zone_suffix}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Application = "openclaw"
    },
    var.additional_tags
  )

  # Security: Gateway port should NEVER be exposed
  gateway_port = 18789
}
