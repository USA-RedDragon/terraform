output "bucket_name" {
  description = "Origin bucket; the deploy step's `aws s3 sync` target."
  value       = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  description = "CloudFront distribution id; the deploy step's `aws cloudfront create-invalidation --distribution-id`."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_domain_name" {
  description = "CloudFront domain name the rustdar CNAME points at."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "deploy_role_arn" {
  description = "Role the rustdar release workflow assumes via GitHub OIDC."
  value       = aws_iam_role.github_actions.arn
}

output "site_url" {
  description = "Public URL of the deployed PWA."
  value       = "https://rustdar.mcswain.dev"
}
