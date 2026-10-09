output "role_arn" {
  description = "Role the deployment and the repository's tests assume."
  value       = aws_iam_role.nexrad_aws_notifier.arn
}
