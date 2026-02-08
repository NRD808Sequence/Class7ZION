############################################
# Lab 3: São Paulo Outputs
# Exported for Tokyo Phase 3 via remote state
############################################

#-----------------------------------------------------------------------------
# VPC OUTPUTS
#-----------------------------------------------------------------------------

output "saopaulo_vpc_id" {
  description = "ID of the Sao Paulo VPC"
  value       = aws_vpc.liberdade_vpc01.id
}

output "saopaulo_vpc_cidr" {
  description = "CIDR of the Sao Paulo VPC"
  value       = aws_vpc.liberdade_vpc01.cidr_block
}

output "saopaulo_public_subnet_ids" {
  description = "IDs of Sao Paulo public subnets"
  value = [
    aws_subnet.liberdade_public_subnet01.id,
    aws_subnet.liberdade_public_subnet02.id
  ]
}

output "saopaulo_private_subnet_ids" {
  description = "IDs of Sao Paulo private subnets"
  value = [
    aws_subnet.liberdade_private_subnet01.id,
    aws_subnet.liberdade_private_subnet02.id
  ]
}

#-----------------------------------------------------------------------------
# EC2 OUTPUTS
#-----------------------------------------------------------------------------

output "saopaulo_ec2_instance_id" {
  description = "ID of the Sao Paulo EC2 instance"
  value       = aws_instance.liberdade_ec201.id
}

#-----------------------------------------------------------------------------
# ALB OUTPUTS
#-----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of Sao Paulo ALB (used by Tokyo CloudFront origin group)"
  value       = aws_lb.liberdade_alb01.dns_name
}

output "alb_arn" {
  description = "ARN of Sao Paulo ALB"
  value       = aws_lb.liberdade_alb01.arn
}

#-----------------------------------------------------------------------------
# TRANSIT GATEWAY OUTPUTS
#-----------------------------------------------------------------------------

output "saopaulo_tgw_id" {
  description = "ID of Sao Paulo Transit Gateway (Liberdade Spoke)"
  value       = aws_ec2_transit_gateway.liberdade_tgw01.id
}

output "tgw_peering_attachment_id" {
  description = "ID of TGW peering attachment (SP->Tokyo request, for Tokyo Phase 3 to accept)"
  value       = aws_ec2_transit_gateway_peering_attachment.liberdade_to_shinjuku_peer01.id
}

#-----------------------------------------------------------------------------
# ALB LOGS OUTPUTS
#-----------------------------------------------------------------------------

output "alb_logs_bucket" {
  description = "ALB access logs S3 bucket name"
  value       = aws_s3_bucket.liberdade_alb_logs.id
}

output "alb_logs_bucket_arn" {
  description = "ALB access logs S3 bucket ARN"
  value       = aws_s3_bucket.liberdade_alb_logs.arn
}

#-----------------------------------------------------------------------------
# WAF OUTPUTS
#-----------------------------------------------------------------------------

output "saopaulo_waf_acl_arn" {
  description = "ARN of Sao Paulo regional WAF"
  value       = aws_wafv2_web_acl.liberdade_sp_waf01.arn
}

#-----------------------------------------------------------------------------
# ORIGIN DNS OUTPUTS
#-----------------------------------------------------------------------------

output "origin_fqdn" {
  description = "Origin FQDN for CloudFront failover (matches ACM wildcard cert)"
  value       = aws_route53_record.liberdade_origin_dns.fqdn
}

#-----------------------------------------------------------------------------
# SNS OUTPUTS
#-----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of SP SNS topic for ALB incident alerts"
  value       = aws_sns_topic.liberdade_sns_topic01.arn
}

#-----------------------------------------------------------------------------
# COMPLIANCE OUTPUTS
#-----------------------------------------------------------------------------

output "appi_compliance_note" {
  description = "APPI compliance status for São Paulo"
  value       = "COMPLIANT - Stateless compute only, no RDS, no PHI storage. Data accessed cross-region from Tokyo via TGW."
}
