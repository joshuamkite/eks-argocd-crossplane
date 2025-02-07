provider "aws" {
  default_tags {
    tags = local.tags
  }
  region = "eu-west-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.86.0"
    }
  }
  required_version = ">= 1.9.0"
}
