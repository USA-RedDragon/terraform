variable "github_repo" {
  description = <<-EOT
    The `owner/name` the release workflow runs in, used as the GitHub OIDC
    subject the deploy role trusts.

    CONFIRM THIS BEFORE THE FIRST APPLY. It is the one value here that fails
    late and confusingly: a wrong subject applies cleanly, and then every deploy
    dies at `configure-aws-credentials` with "Not authorized to perform
    sts:AssumeRoleWithWebIdentity" -- which reads like a broken role, not a
    typo'd repository name.

    The default assumes the repository keeps its name inside the new org. If it
    is renamed on the way over -- `squallar/app`, `squallar/radar` -- set this.
  EOT
  type        = string
  default     = "squallar/squallar"
}
