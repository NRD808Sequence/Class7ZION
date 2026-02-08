# Lab 3: São Paulo Variable Values

project_name = "chewbacca"

# VPC
saopaulo_vpc_cidr             = "10.76.0.0/16"
saopaulo_public_subnet_cidrs  = ["10.76.1.0/24", "10.76.11.0/24"]
saopaulo_private_subnet_cidrs = ["10.76.101.0/24", "10.76.128.0/24"]
saopaulo_azs                  = ["sa-east-1a", "sa-east-1c"]

# EC2
saopaulo_ec2_ami_id = "ami-0c820c196a818d66a"
ec2_instance_type   = "t3.micro"

# DNS
domain_name   = "keepuneat.click"
app_subdomain = "app"

# ALB Logging
alb_access_logs_prefix  = "alb-logs"
alb_logs_retention_days = 90
