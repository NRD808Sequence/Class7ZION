############################################
# Lab 3: Tokyo State — Variables
############################################

#-----------------------------------------------------------------------------
# General Variables
#-----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "chewbacca"
}

#-----------------------------------------------------------------------------
# Phase 3 Toggle
#-----------------------------------------------------------------------------

variable "enable_saopaulo_remote_state" {
  description = "Enable reading São Paulo remote state (set true for Phase 3)"
  type        = bool
  default     = false
}

#-----------------------------------------------------------------------------
# Tokyo VPC Variables
#-----------------------------------------------------------------------------

variable "tokyo_vpc_cidr" {
  description = "VPC CIDR for Tokyo region"
  type        = string
  default     = "10.75.0.0/16"
}

variable "tokyo_public_subnet_cidrs" {
  description = "Public subnet CIDRs for Tokyo"
  type        = list(string)
  default     = ["10.75.1.0/24", "10.75.11.0/24"]
}

variable "tokyo_private_subnet_cidrs" {
  description = "Private subnet CIDRs for Tokyo"
  type        = list(string)
  default     = ["10.75.101.0/24", "10.75.128.0/24"]
}

variable "tokyo_azs" {
  description = "Availability Zones for Tokyo"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

#-----------------------------------------------------------------------------
# EC2 Variables
#-----------------------------------------------------------------------------

variable "tokyo_ec2_ami_id" {
  description = "AMI ID for EC2 in Tokyo (Amazon Linux 2023)"
  type        = string
  default     = "ami-0d52744d6551d851e"
}

variable "ec2_instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

#-----------------------------------------------------------------------------
# RDS Variables (Tokyo Only — APPI Compliance)
#-----------------------------------------------------------------------------

variable "db_engine" {
  description = "RDS engine"
  type        = string
  default     = "mysql"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "labmysql"
}

variable "db_username" {
  description = "DB master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "DB master password — set via TF_VAR_db_password (no default)"
  type        = string
  sensitive   = true
}

#-----------------------------------------------------------------------------
# DNS and TLS Variables
#-----------------------------------------------------------------------------

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "keepuneat.click"
}

variable "app_subdomain" {
  description = "Subdomain for the application"
  type        = string
  default     = "app"
}

#-----------------------------------------------------------------------------
# Notification Variables
#-----------------------------------------------------------------------------

variable "sns_email_endpoint" {
  description = "Email for SNS subscription"
  type        = string
  default     = "gaijinmzungu@gmail.com"
}

variable "my_ip" {
  description = "Your IP address for SSH access (format: x.x.x.x/32)"
  type        = string
  default     = "0.0.0.0/0"
}

#-----------------------------------------------------------------------------
# Logging Variables
#-----------------------------------------------------------------------------

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF logs"
  type        = number
  default     = 30
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logging to S3"
  type        = bool
  default     = false
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb-logs"
}

variable "alb_logs_retention_days" {
  description = "Number of days to retain ALB logs"
  type        = number
  default     = 90
}
