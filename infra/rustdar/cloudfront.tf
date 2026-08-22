resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "rustdar-mcswain-dev-oac"
  description                       = "OAC for the rustdar.mcswain.dev origin bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CROSS-ORIGIN ISOLATION -- the reason this site left GitHub Pages.
#
# COOP: same-origin + COEP: require-corp is what makes `crossOriginIsolated`
# true, which is what unlocks SharedArrayBuffer and therefore wasm threads.
#
# THIS POLICY MUST BE ATTACHED TO EVERY CACHE BEHAVIOUR, NOT A PATH-SCOPED
# SUBSET. Chrome refuses to register a service worker for a cross-origin
# isolated client unless the worker *script response itself* carries a matching
# COEP header, and it fails silently -- registration just never completes, with
# no console error naming headers. sw.js, worker.js and everything under pkg/
# all need it. If a future ordered_cache_behavior is added here, it needs this
# same response_headers_policy_id or service worker registration breaks.
#
# A response headers policy is applied when CloudFront builds the viewer
# response, after the cache lookup, so none of these headers participate in the
# cache key and none of them affect what CloudFront stores.
resource "aws_cloudfront_response_headers_policy" "site" {
  name    = "rustdar-cross-origin-isolation"
  comment = "COOP/COEP isolation + shell cache policy for rustdar.mcswain.dev"

  custom_headers_config {
    items {
      header   = "Cross-Origin-Opener-Policy"
      value    = "same-origin"
      override = true
    }

    items {
      header   = "Cross-Origin-Embedder-Policy"
      value    = "require-corp"
      override = true
    }

    # CACHE-CONTROL IS AN EXPLICIT CHOICE HERE FOR THE FIRST TIME. GitHub Pages
    # emitted whatever it emitted; S3 emits nothing unless the uploader sets it.
    # Setting it here rather than at upload time keeps the decision in review
    # instead of in an `aws s3 cp` flag, and applies it uniformly.
    #
    # Why revalidate-always rather than a long max-age for hashed assets: NOTHING
    # THIS APP SHIPS IS CONTENT-HASHED. The names are fixed -- pkg/rustdar_web.js,
    # pkg/rustdar_web_bg.wasm, worker.js, sw.js, the icons -- because sw.js
    # detects deploys by HEADing pkg/rustdar_web_bg.wasm and the directory index
    # and folding the returned ETag / Last-Modified into a shell-version token.
    # `immutable` on a mutable name would pin clients to a dead build; even a
    # plain long max-age only delays detection, since a stale copy of the wasm
    # is exactly what the token machinery is trying to notice changing.
    #
    # The cost is one conditional request per asset per load, answered 304. The
    # edge absorbs the fan-out (see the cache policy TTLs below), and the deploy
    # workflow's CreateInvalidation makes a new build visible immediately.
    #
    # index.html, sw.js and worker.js in particular must never be long-cached.
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
  name        = "rustdar-revalidate"
  comment     = "Short edge TTL; no asset name in this app is content-hashed"
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
  comment             = "rustdar.mcswain.dev"
  aliases             = ["rustdar.mcswain.dev"]
  default_root_object = "index.html"
  http_version        = "http2and3"

  # North America + Europe. Viewers elsewhere are still served, from a NA/EU
  # edge; the site is a US weather radar client, so the cheaper class fits the
  # audience.
  price_class = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-rustdar"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # One behaviour, no ordered_cache_behavior blocks. Every path gets identical
  # isolation headers and identical cache treatment, which is both what COEP
  # requires of the service worker script and what the un-hashed asset names
  # require of the cache. Adding a path-scoped behaviour later means repeating
  # response_headers_policy_id on it.
  default_cache_behavior {
    target_origin_id       = "s3-rustdar"
    viewer_protocol_policy = "redirect-to-https"

    # HEAD is load-bearing, not boilerplate: sw.js's probeValidator() issues
    # HEAD with cache: "no-store" against pkg/rustdar_web_bg.wasm and the
    # directory index on every update check. A GET-only behaviour would 405
    # those probes and the worker would never see a deploy.
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.site.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
  }

  # Deliberately no custom_error_response mapping 403/404 to index.html. The app
  # has no client-side router that needs it, and rewriting a missing object to a
  # 200 would make probeValidator() read a deleted wasm module as a healthy one.

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

  tags = { Name = "rustdar.mcswain.dev" }
}
