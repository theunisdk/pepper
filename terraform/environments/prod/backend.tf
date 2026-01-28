# Terraform Backend Configuration
#
# For production use, uncomment and configure a remote backend like S3.
# This enables state locking and team collaboration.
#
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "moltbot/prod/terraform.tfstate"
#     region         = "af-south-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }
#
# For now, using local backend (state stored in terraform.tfstate file)
# Make sure to NOT commit terraform.tfstate to version control
