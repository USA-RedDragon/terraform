terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # CloudFront reads certificates only from us-east-1, so the caller has to
      # hand this module a provider pinned there even if the rest of the stack
      # moves region later.
      configuration_aliases = [aws.us_east_1]
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

locals {
  all_domains = concat([var.domain_name], var.additional_domains)
  origin_id   = "s3-${var.bucket_name}"
}

# ---------------------------------------------------------------------------
# Origin bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
  tags   = { Name = var.comment }
}

# Nothing is public. The only reader is the distribution, via the Origin Access
# Control grant in the bucket policy below.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs off entirely: the OAC grant is a bucket policy, and the deploy role writes
# as the bucket owner. Nothing here ever needs an object ACL.
resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Scoped to this one distribution: the service principal alone would let any
# CloudFront distribution in any account read the bucket.
data "aws_iam_policy_document" "site_origin" {
  statement {
    sid       = "AllowCloudFrontOACRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_origin.json

  # The public access block rejects a policy it reads as public while it is
  # still settling; order the two so the grant lands after it.
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------------------------------------------------------------------
# Certificate
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "site" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = var.additional_domains
  validation_method         = "DNS"

  tags = { Name = var.comment }

  lifecycle {
    create_before_destroy = true
  }
}

# One record per distinct validation challenge. `distinct` matters: when a SAN
# shares a parent with the primary name ACM can hand back the same CNAME twice,
# and two Cloudflare records with one name collide on apply.
resource "cloudflare_dns_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options :
    option.domain_name => option
  }

  zone_id = var.zone_id
  # Both the name and the value arrive from ACM with a trailing dot; Cloudflare
  # stores them without one, so trim it or every plan shows a diff.
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 300
  proxied = false
  comment = "ACM DNS validation for ${var.domain_name}"
}

# Blocks until the CNAMEs above have been seen by ACM, so the distribution never
# references an unissued certificate.
resource "aws_acm_certificate_validation" "site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.acm_validation : record.name]
}

# ---------------------------------------------------------------------------
# Edge
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.bucket_name}-oac"
  description                       = "OAC for the ${var.domain_name} origin bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CROSS-ORIGIN ISOLATION -- the reason the app left GitHub Pages.
#
# COOP: same-origin + COEP: require-corp is what makes `crossOriginIsolated`
# true, which is what unlocks SharedArrayBuffer and therefore wasm threads.
#
# WHEN ENABLED, THIS POLICY MUST BE ATTACHED TO EVERY CACHE BEHAVIOUR, NOT A
# PATH-SCOPED SUBSET. Chrome refuses to register a service worker for a cross
# origin isolated client unless the worker *script response itself* carries a
# matching COEP header, and it fails silently -- registration just never
# completes, with no console error naming headers. sw.js, worker.js and
# everything under pkg/ all need it. If an ordered_cache_behavior is ever added
# below, it needs this same response_headers_policy_id or registration breaks.
#
# A response headers policy is applied when CloudFront builds the viewer
# response, after the cache lookup, so none of these headers participate in the
# cache key and none of them affect what CloudFront stores.
resource "aws_cloudfront_response_headers_policy" "site" {
  name    = "${var.bucket_name}-headers"
  comment = "${var.cross_origin_isolation ? "COOP/COEP isolation + " : ""}shell cache policy for ${var.domain_name}"

  custom_headers_config {
    dynamic "items" {
      for_each = var.cross_origin_isolation ? [1] : []
      content {
        header   = "Cross-Origin-Opener-Policy"
        value    = "same-origin"
        override = true
      }
    }

    dynamic "items" {
      for_each = var.cross_origin_isolation ? [1] : []
      content {
        header   = "Cross-Origin-Embedder-Policy"
        value    = "require-corp"
        override = true
      }
    }

    # Cache-Control is set here rather than at upload time so the decision stays
    # in review instead of in an `aws s3 cp` flag, and applies uniformly. S3
    # emits none of its own, so this policy is unopposed.
    #
    # Why revalidate-always rather than a long max-age for hashed assets:
    # NOTHING EITHER SITE SHIPS IS CONTENT-HASHED. The app's names are fixed --
    # pkg/squallar_web.js, pkg/squallar_web_bg.wasm, worker.js, sw.js, the icons
    # -- because sw.js detects deploys by HEADing pkg/squallar_web_bg.wasm and
    # the directory index and folding the returned ETag / Last-Modified into a
    # shell-version token. `immutable` on a mutable name would pin clients to a
    # dead build; even a plain long max-age only delays detection, since a stale
    # copy of the wasm is exactly what the token machinery is trying to notice.
    #
    # The cost is one conditional request per asset per load, answered 304. The
    # edge absorbs the fan-out, and the deploy's CreateInvalidation makes a new
    # build visible immediately.
    items {
      header   = "Cache-Control"
      value    = "public, max-age=0, must-revalidate"
      override = true
    }
  }

  # No remove_headers_config: ETag and Last-Modified must reach the viewer
  # untouched. sw.js's probeValidator() builds its shell-version token out of
  # them, and a response with neither reads to the worker as "nothing changed",
  # forever. (CloudFront may weaken or drop ETag on objects it compressed; S3's
  # Last-Modified survives regardless and validatorToken() falls back to it.)

  security_headers_config {
    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }
  }
}

# Edge caching only -- what the *viewer* is told is the Cache-Control header in
# the response headers policy above.
#
# min_ttl 0 lets an origin Cache-Control shorten this if one is ever set at
# upload time; default_ttl 300 is what actually applies, since S3 objects carry
# no Cache-Control of their own. Five minutes of edge caching plus the deploy
# invalidation is the whole freshness story: without the invalidation this
# number would have to be near zero, because none of the asset names change
# between builds.
resource "aws_cloudfront_cache_policy" "site" {
  name        = "${var.bucket_name}-revalidate"
  comment     = "Short edge TTL; no asset name on this site is content-hashed"
  min_ttl     = 0
  default_ttl = 300
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.comment
  aliases             = local.all_domains
  default_root_object = "index.html"
  http_version        = "http2and3"

  # North America + Europe. Viewers elsewhere are still served, from a NA/EU
  # edge; this is a US weather radar product, so the cheaper class fits the
  # audience.
  price_class = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = local.origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # One behaviour, no ordered_cache_behavior blocks. Every path gets identical
  # headers and identical cache treatment, which is both what COEP requires of
  # the service worker script and what the un-hashed asset names require of the
  # cache. Adding a path-scoped behaviour later means repeating
  # response_headers_policy_id on it.
  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"

    # HEAD is load-bearing on the app, not boilerplate: sw.js's probeValidator()
    # issues HEAD with cache: "no-store" against pkg/squallar_web_bg.wasm and the
    # directory index on every update check. A GET-only behaviour would 405 those
    # probes and the worker would never see a deploy.
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.site.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
  }

  # Deliberately no custom_error_response mapping 403/404 to index.html. Neither
  # site has a client-side router that needs it, and rewriting a missing object
  # to a 200 would make the app's probeValidator() read a deleted wasm module as
  # a healthy one.

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = var.comment }
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

# APEX CNAME. This is the one structural difference from the rustdar module,
# which pointed a subdomain. DNS forbids a CNAME at a zone apex alongside the
# SOA and NS records that must live there, so this only works because Cloudflare
# flattens apex CNAMEs -- it resolves the target itself and answers with A
# records.
#
# Flattening applies to DNS-only records, not just proxied ones, so it does not
# force the grey cloud open. VERIFY THIS ON FIRST APPLY ANYWAY: if the zone's
# "CNAME Flattening" setting is ever narrowed from the apex default, the record
# stops resolving and the site goes dark with a perfectly healthy distribution
# behind it.
#
# DNS-only, never proxied. Proxying would put Cloudflare's edge in front of
# CloudFront: an extra hop for no benefit, and -- the disqualifying part -- a
# second party in a position to add, strip or rewrite response headers. On the
# app that is fatal rather than untidy: losing either of COOP/COEP silently
# drops `crossOriginIsolated` to false and takes wasm threads with it. The
# marketing site keeps the same setting for one reason only, that a split
# convention between two sites in one zone is how the wrong one gets proxied
# later by hand.
resource "cloudflare_dns_record" "site" {
  for_each = toset(local.all_domains)

  zone_id = var.zone_id
  name    = each.value
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  ttl     = 300
  proxied = false
  comment = "${var.comment} -- CloudFront, unproxied so response headers survive"
}
