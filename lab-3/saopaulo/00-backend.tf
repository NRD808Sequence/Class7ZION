############################################
# Lab 3: São Paulo Terraform Backend
# Split-state: separate from Tokyo
############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "class7-armagaggeon-tf-bucket"
    key            = "lab3/saopaulo/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lab3-saopaulo-tf-locks"
    encrypt        = true
  }
}
