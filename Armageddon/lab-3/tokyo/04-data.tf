############################################
# Lab 3: Tokyo State — Data Sources
############################################

#-----------------------------------------------------------------------------
# Route53 Hosted Zone
#-----------------------------------------------------------------------------

data "aws_route53_zone" "chewbacca_zone" {
  name         = var.domain_name
  private_zone = false
}

#-----------------------------------------------------------------------------
# São Paulo Remote State (Phase 3 only)
#-----------------------------------------------------------------------------

data "terraform_remote_state" "saopaulo" {
  count   = var.enable_saopaulo_remote_state ? 1 : 0
  backend = "s3"

  config = {
    bucket = "class7-armagaggeon-tf-bucket"
    key    = "lab3/saopaulo/terraform.tfstate"
    region = "us-east-1"
  }
}
