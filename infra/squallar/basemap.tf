locals {
  cloudflare_account_id = data.cloudflare_zone.squallar_app.account.id
}

resource "cloudflare_r2_bucket" "basemap" {
  account_id = local.cloudflare_account_id
  name       = "squallar-basemap"

  storage_class = "Standard"
}

resource "cloudflare_r2_managed_domain" "basemap" {
  account_id  = local.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.basemap.name
  enabled     = false
}

resource "cloudflare_r2_custom_domain" "basemap" {
  account_id  = local.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.basemap.name
  domain      = var.basemap_domain
  zone_id     = data.cloudflare_zone.squallar_app.zone_id
  enabled     = true

  min_tls = "1.2"
}

resource "cloudflare_r2_bucket_cors" "basemap" {
  account_id  = local.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.basemap.name

  rules = [
    {
      id = "app-range-reads"

      allowed = {
        origins = var.basemap_cors_origins
        methods = ["GET", "HEAD"]
        headers = ["range"]
      }

      expose_headers = ["content-range", "accept-ranges", "etag"]

      max_age_seconds = 86400
    }
  ]
}
