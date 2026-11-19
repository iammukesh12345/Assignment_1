terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "assignment_user"

  default_tags {
    tags = {
      Project     = "EmployeeManagement"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}
