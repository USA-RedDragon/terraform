# The account already federates GitHub Actions -- github-actions-astro-garden
# assumes through this same provider -- so it is read, never declared. Declaring
# it a second time would collide on apply.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to the one repository. To narrow further to the branch that
    # actually deploys, replace the wildcard with
    # "repo:USA-RedDragon/rustdar:ref:refs/heads/main".
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:USA-RedDragon/rustdar:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-rustdar"
  description        = "Deploy role for USA-RedDragon/rustdar -> rustdar.mcswain.dev"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = { Name = "github-actions-rustdar" }
}

data "aws_iam_policy_document" "github_actions_deploy" {
  # Write the site. ListBucket is on the bucket itself, not its objects, and is
  # what `aws s3 sync --delete` needs to see which keys are already there.
  statement {
    sid = "SyncObjects"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${module.site.bucket_arn}/*"]
  }

  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [module.site.bucket_arn]
  }

  # Every deploy has to invalidate: none of the asset names change between
  # builds, so the edge would otherwise serve the previous build for the length
  # of the cache policy's default TTL.
  statement {
    sid       = "InvalidateEdge"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [module.site.distribution_arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "rustdar-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
