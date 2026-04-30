terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.43.0"
    }
  }

  backend "s3" {
    region = "us-east-1"
    bucket = "mcswain-dev-tf-states"
    key    = "aws-spot"
  }
}
