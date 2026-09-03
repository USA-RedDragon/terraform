terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.63.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.24.0"
    }
  }

  backend "s3" {
    region = "us-east-1"
    bucket = "mcswain-dev-tf-states"
    key    = "rustdar"
  }
}

provider "aws" {
  region = "us-east-1"
}

# CloudFront only accepts an ACM certificate that lives in us-east-1, no matter
# where the distribution's viewers or its origin bucket are. Everything in this
# module is us-east-1 anyway, so this alias is redundant today -- it exists so
# that the certificate keeps its required region if the default one ever moves.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Credentials come from the environment: CLOUDFLARE_API_TOKEN. The terraform
# workflow does not set it yet -- see README, "What this module cannot do".
provider "cloudflare" {}
