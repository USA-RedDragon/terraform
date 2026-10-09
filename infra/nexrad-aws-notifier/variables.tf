variable "github_repo" {
  description = <<-EOT
    The repository whose workflows may assume the role, as it appears in the
    GitHub OIDC subject after `repo:`. Read it from Settings -> Actions ->
    "Default subject claim prefix" rather than assembling it by hand.
  EOT
  type        = string
  default     = "USA-RedDragon/nexrad-aws-notifier"
}
