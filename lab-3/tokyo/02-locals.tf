############################################
# Lab 3: Tokyo State — Locals and Tags
############################################

locals {
  # Naming prefixes
  tokyo_prefix     = "chewbacca"
  tokyo_tgw_prefix = "shinjuku"

  # Common tags
  common_tags = {
    Lab         = "lab3-multi-region"
    Environment = "development"
    Project     = var.project_name
  }

  # Tokyo-specific tags
  tokyo_tags = merge(local.common_tags, {
    Region = "ap-northeast-1"
    Prefix = local.tokyo_prefix
  })

  # Route53 zone
  chewbacca_zone_id  = data.aws_route53_zone.chewbacca_zone.zone_id
  chewbacca_app_fqdn = "${var.app_subdomain}.${var.domain_name}"

  # ELB account IDs per region for ALB logging
  elb_account_id = {
    "ap-northeast-1" = "582318560864"
    "sa-east-1"      = "507241528517"
    "us-east-1"      = "127311923021"
  }

  # ── Phase 3 resolution (São Paulo remote state) ──
  resolved_sp_alb_dns    = try(data.terraform_remote_state.saopaulo[0].outputs.alb_dns_name, "")
  resolved_sp_peering_id = try(data.terraform_remote_state.saopaulo[0].outputs.tgw_peering_attachment_id, "")
  resolved_sp_vpc_cidr   = try(data.terraform_remote_state.saopaulo[0].outputs.vpc_cidr, "")
  phase3_active          = var.enable_saopaulo_remote_state && local.resolved_sp_alb_dns != ""
}

# Data sources for account identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
