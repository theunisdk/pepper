locals {
  name_prefix = "${var.project_name}-${var.environment}"
  az          = "${var.aws_region}${var.availability_zone_suffix}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Application = "moltbot-docker-host"
    },
    var.additional_tags
  )

  # Generate docker-compose content from bot list
  docker_compose_content = templatefile("${path.module}/../../../docker/docker-compose.yml.tftpl", {
    bots      = var.bots
    image     = var.docker_image
    timestamp = timestamp()
  })

  # Build SSH tunnel commands for each bot
  bot_tunnel_commands = {
    for bot in var.bots : bot.name => "ssh -i ${pathexpand(var.ssh_private_key_path)} -L ${bot.port}:127.0.0.1:${bot.port} ubuntu@PUBLIC_IP -N"
  }
}
