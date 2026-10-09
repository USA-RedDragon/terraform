# Both providers already exist in the account and other roles assume through
# them, so they are read, never declared.
data "aws_iam_openid_connect_provider" "k8s" {
  url = "https://k8s-oidc.mcswain.dev"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "assume" {
  # The deployment, through its service account on the home cluster.
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.k8s.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "k8s-oidc.mcswain.dev:sub"
      values   = ["system:serviceaccount:nexrad-aws-notifier:nexrad-aws-notifier"]
    }

    condition {
      test     = "StringEquals"
      variable = "k8s-oidc.mcswain.dev:aud"
      values   = ["sts.amazonaws.com"]
    }
  }

  # The repository's tests, which create and tear down real queues and
  # subscriptions. Pushes to main and pull requests from branches in the
  # repository; forks get no OIDC token at all.
  #
  # The repository predates 2026-07-15, so its subject is the `owner/name`
  # form, not the numeric one squallar has to use.
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

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "nexrad_aws_notifier" {
  name               = "nexrad-aws-notifier"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Unchanged from the role as it was created by hand. Each instance makes its
# own two queues, named with a fresh UUID, and subscribes them to the public
# NOAA topics, which live in another account.
data "aws_iam_policy_document" "permissions" {
  statement {
    sid = "ManageOwnEventQueues"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
    ]
    resources = ["arn:aws:sqs:us-east-1:803205869942:nexrad-aws-notifier-events-*"]
  }

  statement {
    sid = "SubscribeToPublicNexradTopics"
    actions = [
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:SetSubscriptionAttributes",
    ]
    resources = [
      "arn:aws:sns:us-east-1:684042711724:NewNEXRADLevel2Archive",
      "arn:aws:sns:us-east-1:684042711724:NewNEXRADLevel2Archive:*",
      "arn:aws:sns:us-east-1:684042711724:NewNEXRADLevel2ObjectFilterable",
      "arn:aws:sns:us-east-1:684042711724:NewNEXRADLevel2ObjectFilterable:*",
    ]
  }
}

resource "aws_iam_role_policy" "nexrad_aws_notifier" {
  name   = "nexrad-aws-notifierPolicy"
  role   = aws_iam_role.nexrad_aws_notifier.id
  policy = data.aws_iam_policy_document.permissions.json
}
