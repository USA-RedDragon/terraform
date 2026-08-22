# The origin bucket is named for the site, matching the astro.garden sibling, so
# that the deploy step reads `aws s3 sync --delete dist/ s3://rustdar.mcswain.dev`.
#
# The dots are worth one eye open at first apply. S3's virtual-hosted endpoint
# for this bucket is rustdar.mcswain.dev.s3.us-east-1.amazonaws.com, and the
# wildcard certificate S3 presents matches one label, not four -- which is why
# S3's own naming rules tell you to avoid periods in buckets fronted by
# CloudFront. astro.garden has carried a dotted name in this account for years,
# so the pattern is not obviously broken; but if the distribution answers 502
# with an origin SSL handshake error, the fix is to rename this bucket to
# rustdar-mcswain-dev and update the deploy target to match. Nothing else in
# this module depends on the name.
resource "aws_s3_bucket" "site" {
  bucket = "rustdar.mcswain.dev"
  tags   = { Name = "rustdar.mcswain.dev" }
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
