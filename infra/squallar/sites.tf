# Looked up by name rather than pinned to a zone id: the id is an opaque
# Cloudflare-side value that nothing in this repo should be carrying around.
#
# PREREQUISITE: both domains must already exist as zones in Cloudflare, with
# their registrar nameservers delegated there. Terraform reads these zones, it
# does not create them, so a domain that is still parked at its registrar fails
# the plan with a zone-not-found rather than doing anything clever.
data "cloudflare_zone" "squallar_app" {
  filter = {
    name = "squallar.app"
  }
}

data "cloudflare_zone" "squallar_com" {
  filter = {
    name = "squallar.com"
  }
}

# The PWA. Cross-origin isolated, because wasm threads depend on it.
module "app" {
  source = "../../modules/static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
    cloudflare    = cloudflare
  }

  domain_name            = "squallar.app"
  bucket_name            = "squallar-app-origin"
  zone_id                = data.cloudflare_zone.squallar_app.zone_id
  cross_origin_isolation = true
  comment                = "squallar.app"
}

# The marketing site. Answers on the apex and on www, because a bare
# www.squallar.com that does not resolve is a worse first impression than the
# redundant name is untidy.
module "www" {
  source = "../../modules/static-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
    cloudflare    = cloudflare
  }

  domain_name            = "squallar.com"
  additional_domains     = ["www.squallar.com"]
  bucket_name            = "squallar-com-origin"
  zone_id                = data.cloudflare_zone.squallar_com.zone_id
  cross_origin_isolation = false
  comment                = "squallar.com"
}
