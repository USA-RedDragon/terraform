output "bucket_name" {
  description = "Origin bucket; the deploy step's `aws s3 sync` target."
  value       = module.site.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution id; the deploy step's `aws cloudfront create-invalidation --distribution-id`."
  value       = module.site.distribution_id
}

output "distribution_domain_name" {
  description = "CloudFront domain name the rustdar CNAME points at."
  value       = module.site.distribution_domain_name
}

output "deploy_role_arn" {
  description = "Role the rustdar release workflow assumes via GitHub OIDC."
  value       = aws_iam_role.github_actions.arn
}

output "site_url" {
  description = "Public URL of the deployed PWA."
  value       = "https://rustdar.mcswain.dev"
}
