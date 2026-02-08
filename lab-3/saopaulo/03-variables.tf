############################################
# Lab 3: São Paulo Variables
# NO db_password — APPI compliance (data stays in Tokyo)
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
# São Paulo VPC Variables
#-----------------------------------------------------------------------------

variable "saopaulo_vpc_cidr" {
  description = "VPC CIDR for São Paulo region"
  type        = string
  default     = "10.76.0.0/16"
}

variable "saopaulo_public_subnet_cidrs" {
  description = "Public subnet CIDRs for São Paulo"
  type        = list(string)
  default     = ["10.76.1.0/24", "10.76.11.0/24"]
}

variable "saopaulo_private_subnet_cidrs" {
  description = "Private subnet CIDRs for São Paulo"
  type        = list(string)
  default     = ["10.76.101.0/24", "10.76.128.0/24"]
}

variable "saopaulo_azs" {
  description = "Availability Zones for São Paulo"
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1c"]
}

#-----------------------------------------------------------------------------
# EC2 Variables
#-----------------------------------------------------------------------------

variable "saopaulo_ec2_ami_id" {
  description = "AMI ID for EC2 in São Paulo (Amazon Linux 2023)"
  type        = string
  default     = "ami-0c820c196a818d66a"
}

variable "ec2_instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
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

#-----------------------------------------------------------------------------
# Logging Variables
#-----------------------------------------------------------------------------

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
