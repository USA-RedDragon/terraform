# The account already federates GitHub Actions -- github-actions-astro-garden
# and github-actions-rustdar both assume through this same provider -- so it is
# read, never declared. Declaring it a second time would collide on apply.
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

    # Scoped to the one repository, by the numeric ids GitHub bakes into the
    # subject for repositories created after 2026-07-15 -- see `github_repo`.
    # The wildcard covers the ref suffix; to narrow further to the branch that
    # actually deploys, replace it with
    # "repo:${var.github_repo}:ref:refs/heads/main".
    #
    # NOT widened to `repo:Squallar@320083733/*`. That would spare us knowing
    # the repository id, at the cost of letting any repo in the org -- including
    # one that does not exist yet, and including a fork someone pushes into it
    # -- deploy over the production site.
    #
    # `StringLike` is case-sensitive. The owner is `Squallar`, capital S.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

# ONE role for both sites, not two. The same workflow in the same repository
# publishes both, so a second role would be a second thing to rotate and a
# second ARN to keep in sync in build.yaml, buying no isolation that the
# per-resource statements below do not already give.
resource "aws_iam_role" "github_actions" {
  name               = "github-actions-squallar"
  description        = "Deploy role for ${var.github_repo} -> squallar.app + squallar.com"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = { Name = "github-actions-squallar" }
}

data "aws_iam_policy_document" "github_actions_deploy" {
  # Write both sites. ListBucket is on the buckets themselves, not their
  # objects, and is what `aws s3 sync --delete` needs to see which keys are
  # already there.
  statement {
    sid = "SyncObjects"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [
      "${module.app.bucket_arn}/*",
      "${module.www.bucket_arn}/*",
    ]
  }

  statement {
    sid     = "ListBucket"
    actions = ["s3:ListBucket"]
    resources = [
      module.app.bucket_arn,
      module.www.bucket_arn,
    ]
  }

  # Every deploy has to invalidate: none of the asset names change between
  # builds, so the edge would otherwise serve the previous build for the length
  # of the cache policy's default TTL.
  statement {
    sid     = "InvalidateEdge"
    actions = ["cloudfront:CreateInvalidation"]
    resources = [
      module.app.distribution_arn,
      module.www.distribution_arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "squallar-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
