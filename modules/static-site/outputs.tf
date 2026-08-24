output "bucket_name" {
  description = "Origin bucket; the deploy step's `aws s3 sync` target."
  value       = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  description = "Origin bucket ARN, for the deploy role's object statements."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "CloudFront distribution id; the deploy step's `aws cloudfront create-invalidation --distribution-id`."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  description = "Distribution ARN, for the deploy role's CreateInvalidation statement."
  value       = aws_cloudfront_distribution.site.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name the apex CNAME is flattened onto."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "Public URL."
  value       = "https://${var.domain_name}"
}
