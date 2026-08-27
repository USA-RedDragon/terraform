# These five are what build.yaml's deploy jobs need. The workflow hardcodes
# them as literals rather than reading state, so after the first apply they have
# to be copied across by hand -- see README.
output "deploy_role_arn" {
  description = "Role both deploy jobs assume via GitHub OIDC."
  value       = aws_iam_role.github_actions.arn
}

output "app_bucket_name" {
  description = "squallar.app origin bucket; the app deploy's `aws s3 sync` target."
  value       = module.app.bucket_name
}

output "app_distribution_id" {
  description = "squallar.app distribution id; the app deploy's `create-invalidation --distribution-id`."
  value       = module.app.distribution_id
}

output "www_bucket_name" {
  description = "squallar.com origin bucket; the marketing deploy's `aws s3 sync` target."
  value       = module.www.bucket_name
}

output "www_distribution_id" {
  description = "squallar.com distribution id; the marketing deploy's `create-invalidation --distribution-id`."
  value       = module.www.distribution_id
}

output "app_distribution_domain_name" {
  description = "CloudFront domain the squallar.app apex CNAME is flattened onto."
  value       = module.app.distribution_domain_name
}

output "www_distribution_domain_name" {
  description = "CloudFront domain the squallar.com apex CNAME is flattened onto."
  value       = module.www.distribution_domain_name
}

output "basemap_bucket_name" {
  description = "R2 bucket holding the basemap `.pmtiles` generations."
  value       = cloudflare_r2_bucket.basemap.name
}

output "basemap_url" {
  description = "Origin the app fetches basemap ranges from. Custom domain only; the r2.dev managed domain is asserted off."
  value       = "https://${cloudflare_r2_custom_domain.basemap.domain}"
}
