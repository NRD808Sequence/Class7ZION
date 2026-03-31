############################################
# Lab 3: São Paulo Provider Configuration
# sa-east-1 is the DEFAULT provider (no alias)
############################################

provider "aws" {
  region = "sa-east-1"

  default_tags {
    tags = {
      Managedby   = "Terraform"
      Lab         = "lab3-multi-region"
      Environment = "development"
    }
  }
}
