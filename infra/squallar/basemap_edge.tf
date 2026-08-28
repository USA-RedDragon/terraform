locals {
  basemap_host_expr      = "http.host eq \"${var.basemap_domain}\""
  basemap_immutable_expr = "(starts_with(http.request.uri.path, \"/basemap/\") or starts_with(http.request.uri.path, \"/terrain/\"))"
  basemap_status_expr    = "starts_with(http.request.uri.path, \"/status/\")"
}

resource "cloudflare_ruleset" "basemap_cache" {
  zone_id = data.cloudflare_zone.squallar_app.zone_id
  name    = "basemap archive cache"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      ref         = "basemap_immutable"
      description = "Immutable generation-keyed archives: cache hard, client-side above all"
      expression  = "${local.basemap_host_expr} and ${local.basemap_immutable_expr}"
      enabled     = true
      action      = "set_cache_settings"

      action_parameters = {
        cache = true

        edge_ttl = {
          mode    = "override_origin"
          default = 31536000
          status_code_ttl = [
            {
              status_code_range = {
                from = 400
                to   = 599
              }
              value = 0
            }
          ]
        }

        browser_ttl = {
          mode    = "override_origin"
          default = 31536000
        }
      }
    },

    {
      ref         = "basemap_status_pointer"
      description = "Mutable generation pointer: edge absorbs the boot stampede, client always asks"
      expression  = "${local.basemap_host_expr} and ${local.basemap_status_expr}"
      enabled     = true
      action      = "set_cache_settings"

      action_parameters = {
        cache = true

        edge_ttl = {
          mode = "respect_origin"
          status_code_ttl = [
            {
              status_code_range = {
                from = 400
                to   = 599
              }
              value = 0
            }
          ]
        }

        browser_ttl = {
          mode    = "override_origin"
          default = 0
        }
      }
    }
  ]
}

resource "cloudflare_ruleset" "basemap_ratelimit" {
  zone_id = data.cloudflare_zone.squallar_app.zone_id
  name    = "basemap archive rate limit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "basemap_per_ip"
      description = "Per-IP ceiling on archive range reads; bounds single-host abuse, not a distributed flood"
      expression  = "${local.basemap_host_expr} and ${local.basemap_immutable_expr}"
      enabled     = true
      action      = "block"

      ratelimit = {
        characteristics = ["cf.colo.id", "ip.src"]

        period              = 10
        requests_per_period = floor(var.basemap_ratelimit_per_minute / 6)

        mitigation_timeout = 10
        requests_to_origin = false
      }
    }
  ]
}

resource "cloudflare_tiered_cache" "squallar_app" {
  zone_id = data.cloudflare_zone.squallar_app.zone_id
  value   = "on"
}
