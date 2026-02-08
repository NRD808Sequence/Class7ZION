############################################
# Lab 3: São Paulo Locals
############################################

locals {
  # São Paulo naming prefix
  saopaulo_prefix = "liberdade"

  # TGW naming prefix
  saopaulo_tgw_prefix = "liberdade"

  # Common tags
  common_tags = {
    Lab         = "lab3-multi-region"
    Environment = "development"
    Project     = var.project_name
  }

  # São Paulo-specific tags
  saopaulo_tags = merge(local.common_tags, {
    Region = "sa-east-1"
    Prefix = local.saopaulo_prefix
  })

  # Resolved values from Tokyo remote state
  tokyo_tgw_id   = data.terraform_remote_state.tokyo.outputs.tokyo_tgw_id
  tokyo_vpc_cidr = data.terraform_remote_state.tokyo.outputs.tokyo_vpc_cidr
  origin_secret  = data.terraform_remote_state.tokyo.outputs.origin_secret

  # ELB account ID for sa-east-1 (ALB access logs)
  elb_account_id_sa_east_1 = "507241528517"
}

# Data sources for account identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
