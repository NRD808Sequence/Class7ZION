############################################
# Lab 3: Tokyo State — Outputs
# Exports for SP remote state + verification
############################################

#-----------------------------------------------------------------------------
# VPC OUTPUTS
#-----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the Tokyo VPC"
  value       = aws_vpc.chewbacca_vpc01.id
}

output "vpc_cidr" {
  description = "CIDR of the Tokyo VPC"
  value       = aws_vpc.chewbacca_vpc01.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of Tokyo public subnets"
  value = [
    aws_subnet.chewbacca_public_subnet01.id,
    aws_subnet.chewbacca_public_subnet02.id
  ]
}

output "private_subnet_ids" {
  description = "IDs of Tokyo private subnets"
  value = [
    aws_subnet.chewbacca_private_subnet01.id,
    aws_subnet.chewbacca_private_subnet02.id
  ]
}

#-----------------------------------------------------------------------------
# EC2 OUTPUTS
#-----------------------------------------------------------------------------

output "ec2_instance_id" {
  description = "ID of the Tokyo EC2 instance"
  value       = aws_instance.chewbacca_ec201.id
}

#-----------------------------------------------------------------------------
# RDS OUTPUTS (APPI COMPLIANCE)
#-----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS endpoint address (Tokyo only — APPI compliance)"
  value       = aws_db_instance.chewbacca_rds01.address
}

output "rds_port" {
  description = "RDS port number"
  value       = aws_db_instance.chewbacca_rds01.port
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.chewbacca_rds01.identifier
}

#-----------------------------------------------------------------------------
# ALB OUTPUTS
#-----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of Tokyo ALB"
  value       = aws_lb.chewbacca_alb01.dns_name
}

#-----------------------------------------------------------------------------
# TRANSIT GATEWAY OUTPUTS — consumed by SP remote state
#-----------------------------------------------------------------------------

output "tgw_id" {
  description = "ID of Tokyo Transit Gateway (Shinjuku Hub)"
  value       = aws_ec2_transit_gateway.shinjuku_tgw01.id
}

#-----------------------------------------------------------------------------
# ORIGIN SECRET — consumed by SP remote state
#-----------------------------------------------------------------------------

output "origin_secret" {
  description = "Origin header secret for CloudFront origin cloaking"
  value       = random_password.chewbacca_origin_header_value01.result
  sensitive   = true
}

#-----------------------------------------------------------------------------
# CLOUDFRONT OUTPUTS
#-----------------------------------------------------------------------------

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.chewbacca_cf01.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.chewbacca_cf01.domain_name
}

#-----------------------------------------------------------------------------
# APPLICATION URLs
#-----------------------------------------------------------------------------

output "app_url" {
  description = "Application URL via CloudFront"
  value       = "https://${var.app_subdomain}.${var.domain_name}"
}

output "root_url" {
  description = "Root domain URL via CloudFront"
  value       = "https://${var.domain_name}"
}

#-----------------------------------------------------------------------------
# SECURITY OUTPUTS
#-----------------------------------------------------------------------------

output "rds_sg_id" {
  description = "ID of Tokyo RDS security group"
  value       = aws_security_group.chewbacca_rds_sg01.id
}

#-----------------------------------------------------------------------------
# MONITORING OUTPUTS
#-----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of Tokyo SNS topic for alerts"
  value       = aws_sns_topic.chewbacca_sns_topic01.arn
}

output "log_group_name" {
  description = "Name of Tokyo CloudWatch log group"
  value       = aws_cloudwatch_log_group.chewbacca_log_group01.name
}

#-----------------------------------------------------------------------------
# PHASE 3 STATUS
#-----------------------------------------------------------------------------

output "phase3_active" {
  description = "Whether Phase 3 (cross-region) is active"
  value       = local.phase3_active
}

#-----------------------------------------------------------------------------
# VERIFICATION COMMANDS
#-----------------------------------------------------------------------------

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    rds_tokyo_check    = "aws rds describe-db-instances --region ap-northeast-1 --query 'DBInstances[].DBInstanceIdentifier'"
    rds_saopaulo_check = "aws rds describe-db-instances --region sa-east-1 --query 'DBInstances[].DBInstanceIdentifier' # Should be empty"
    tgw_check          = "aws ec2 describe-transit-gateways --region ap-northeast-1 --query 'TransitGateways[].TransitGatewayId'"
    cloudfront_check   = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.chewbacca_cf01.id} --query 'Distribution.DistributionConfig.Origins'"
  }
}
