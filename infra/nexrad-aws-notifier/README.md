# NEXRAD AWS Notifier

The IAM role [nexrad-aws-notifier](https://github.com/USA-RedDragon/nexrad-aws-notifier) runs as, assumed both by its deployment on the home cluster (through the `k8s-oidc.mcswain.dev` provider) and by the repository's GitHub Actions tests.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.68.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.68.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.nexrad_aws_notifier](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.nexrad_aws_notifier](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/iam_role_policy) | resource |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/iam_openid_connect_provider) | data source |
| [aws_iam_openid_connect_provider.k8s](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/iam_openid_connect_provider) | data source |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.permissions](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | The repository whose workflows may assume the role, as it appears in the<br>GitHub OIDC subject after `repo:`. Read it from Settings -> Actions -><br>"Default subject claim prefix" rather than assembling it by hand. | `string` | `"USA-RedDragon/nexrad-aws-notifier"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | Role the deployment and the repository's tests assume. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
