# Looked up by name rather than pinned to a zone id: the id is an opaque
# Cloudflare-side value that nothing in this repo should be carrying around.
data "cloudflare_zone" "mcswain_dev" {
  filter = {
    name = "mcswain.dev"
  }
}

# ACM's DNS challenge. One record per domain on the certificate (one today).
# Both the name and the value arrive from ACM with a trailing dot; Cloudflare
# stores them without one, so trim it or every plan shows a diff.
resource "cloudflare_dns_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options :
    option.domain_name => option
  }

  zone_id = data.cloudflare_zone.mcswain_dev.zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 300
  proxied = false
  comment = "ACM DNS validation for rustdar.mcswain.dev"
}

# DNS-only, never proxied. Proxying would put Cloudflare's edge in front of
# CloudFront: an extra hop for no benefit, and -- the disqualifying part -- a
# second party in a position to add, strip or rewrite response headers. The
# COOP/COEP pair this distribution exists to set is exactly the kind of header
# that machinery touches, and losing either one silently drops
# `crossOriginIsolated` to false and takes wasm threads with it.
resource "cloudflare_dns_record" "rustdar" {
  zone_id = data.cloudflare_zone.mcswain_dev.zone_id
  name    = "rustdar.mcswain.dev"
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  ttl     = 300
  proxied = false
  comment = "rustdar PWA -- CloudFront, unproxied so COOP/COEP survive"
}
