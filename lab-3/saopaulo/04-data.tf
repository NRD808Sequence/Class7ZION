############################################
# Lab 3: São Paulo Data Sources
# Reads Tokyo remote state for cross-region values
############################################

data "terraform_remote_state" "tokyo" {
  backend = "s3"

  config = {
    bucket = "class7-armagaggeon-tf-bucket"
    key    = "lab3/tokyo/terraform.tfstate"
    region = "us-east-1"
  }
}

# Route53 zone (global — same zone used by both regions)
data "aws_route53_zone" "chewbacca_zone" {
  name         = var.domain_name
  private_zone = false
}
