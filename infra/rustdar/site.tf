# Looked up by name rather than pinned to a zone id: the id is an opaque
# Cloudflare-side value that nothing in this repo should be carrying around.
data "cloudflare_zone" "mcswain_dev" {
  filter = {
    name = "mcswain.dev"
  }
}

# ADOPTED, NOT REBUILT. Everything this module manages here was already applied
# before the module existed; `moved.tf` re-addresses it in state rather than
# letting Terraform destroy and recreate the origin that is currently serving
# the app. The four name overrides below are the other half of that: a `moved`
# block moves a resource without touching its attributes, so the module has to
# be told the names these resources already carry.
#
# The dotted bucket name is the one thing here that would not be chosen again.
# S3's virtual-hosted endpoint for it is
# rustdar.mcswain.dev.s3.us-east-1.amazonaws.com and the wildcard certificate S3
# presents matches a single label, which is why S3's own guidance is to avoid
# periods in buckets fronted by CloudFront. It has worked in this account for
# years, so it stays -- renaming a bucket is a migration, not an edit, and this
# origin is on its way to being a tombstone anyway.
module "site" {
  source = "../../modules/static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
    cloudflare    = cloudflare
  }

  domain_name            = "rustdar.mcswain.dev"
  bucket_name            = "rustdar.mcswain.dev"
  zone_id                = data.cloudflare_zone.mcswain_dev.zone_id
  cross_origin_isolation = true
  comment                = "rustdar.mcswain.dev"

  oac_name                     = "rustdar-mcswain-dev-oac"
  response_headers_policy_name = "rustdar-cross-origin-isolation"
  cache_policy_name            = "rustdar-revalidate"
  origin_id                    = "s3-rustdar"
}
