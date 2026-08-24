# Re-addressing only. Every resource below already exists and is already
# applied; these blocks tell Terraform that the thing formerly at the root
# address is the same object now living inside `module.site`.
#
# WITHOUT THESE THE PLAN IS A DESTROY AND RECREATE OF THE LIVE SITE. Terraform
# does not infer that `aws_s3_bucket.site` and `module.site.aws_s3_bucket.site`
# are one object -- it reads the first as removed and the second as new. For the
# bucket that means an S3 delete, and the deploy artifact does not exist anywhere
# else; for the distribution it means a new CloudFront domain name, which the
# apex CNAME would not be pointing at.
#
# `terraform plan` after this change must report "0 to add, 0 to change,
# 0 to destroy" apart from the handful of metadata `comment` strings the module
# words differently. Anything else means a `moved` block is missing or its key
# is wrong -- do not apply through it.

moved {
  from = aws_s3_bucket.site
  to   = module.site.aws_s3_bucket.site
}

moved {
  from = aws_s3_bucket_public_access_block.site
  to   = module.site.aws_s3_bucket_public_access_block.site
}

moved {
  from = aws_s3_bucket_ownership_controls.site
  to   = module.site.aws_s3_bucket_ownership_controls.site
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.site
  to   = module.site.aws_s3_bucket_server_side_encryption_configuration.site
}

moved {
  from = aws_s3_bucket_policy.site
  to   = module.site.aws_s3_bucket_policy.site
}

moved {
  from = aws_acm_certificate.site
  to   = module.site.aws_acm_certificate.site
}

moved {
  from = aws_acm_certificate_validation.site
  to   = module.site.aws_acm_certificate_validation.site
}

moved {
  from = aws_cloudfront_origin_access_control.site
  to   = module.site.aws_cloudfront_origin_access_control.site
}

moved {
  from = aws_cloudfront_response_headers_policy.site
  to   = module.site.aws_cloudfront_response_headers_policy.site
}

moved {
  from = aws_cloudfront_cache_policy.site
  to   = module.site.aws_cloudfront_cache_policy.site
}

moved {
  from = aws_cloudfront_distribution.site
  to   = module.site.aws_cloudfront_distribution.site
}

# for_each on both sides, keyed by ACM's `domain_name`. The key is unchanged, so
# the whole collection moves in one block.
moved {
  from = cloudflare_dns_record.acm_validation
  to   = module.site.cloudflare_dns_record.acm_validation
}

# The one address that changes SHAPE, not just prefix. This record was a single
# resource named for the site; in the module it is one element of a for_each
# over every domain the distribution answers for, so it acquires a key.
moved {
  from = cloudflare_dns_record.rustdar
  to   = module.site.cloudflare_dns_record.site["rustdar.mcswain.dev"]
}
