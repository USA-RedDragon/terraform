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

  # A separate state from `rustdar`, deliberately. The rustdar stack does not go
  # away when this one lands -- it keeps serving until squallar.app is proven,
  # and then keeps existing as the tombstone origin that redirects the people who
  # still have the old service worker installed. Two lifecycles, two states.
  backend "s3" {
    region = "us-east-1"
    bucket = "mcswain-dev-tf-states"
    key    = "squallar"
  }
}

provider "aws" {
  region = "us-east-1"
}

# CloudFront only accepts an ACM certificate that lives in us-east-1, no matter
# where the distribution's viewers or its origin bucket are. Everything here is
# us-east-1 anyway, so this alias is redundant today -- it exists so that the
# certificates keep their required region if the default one ever moves.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Credentials come from the environment: CLOUDFLARE_API_TOKEN, which the
# terraform workflow does supply.
provider "cloudflare" {}
