terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.62.0"
    }
    # Only to zip the heartbeat function. Pinned like everything else rather
    # than left to float, because an unpinned provider is one more input that
    # can change the deployed artifact without a commit here.
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }

  backend "s3" {
    region = "us-east-1"
    bucket = "mcswain-dev-tf-states"
    key    = "squallar-basemap-spot"
  }
}
