############################################
# Lab 3: Tokyo State — Provider Configuration
# Default = ap-northeast-1, Alias = us-east-1 (CloudFront certs)
############################################

# Tokyo provider (default) — Primary region for data sovereignty (APPI)
provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Managedby   = "Terraform"
      Lab         = "lab3-multi-region"
      Environment = "development"
    }
  }
}

# US-East-1 provider — Required for CloudFront ACM certificates
provider "aws" {
  alias  = "useast1"
  region = "us-east-1"

  default_tags {
    tags = {
      Managedby   = "Terraform"
      Lab         = "lab3-multi-region"
      Environment = "development"
    }
  }
}
