# ---------------------------------------------------------------------------
# The build box's own role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "squallar-basemap-build"
  description        = "Planet build instance: read two SSM params, terminate itself, write logs"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  tags               = { Name = "squallar-basemap-build" }
}

data "aws_iam_policy_document" "instance" {
  # The two credentials, by exact ARN. Not a path wildcard: `/squallar/basemap/*`
  # would silently widen as parameters are added under it.
  statement {
    sid       = "ReadItsOwnCredentials"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [local.r2_param_arn, local.smtp_param_arn]
  }

  # SecureString is useless without the key that decrypts it. Scoped by the
  # service the request came through, so this grants nothing outside SSM.
  statement {
    sid       = "DecryptThoseTwo"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }

  # SELF-TERMINATION, and the condition is what keeps it from being a
  # fleet-wide kill switch. Without the tag condition this role could terminate
  # any instance in the account; with it, only instances this stack launched.
  #
  # It is the happy path only. The dead-man `shutdown -h` in user-data needs no
  # permission at all, because `instance_initiated_shutdown_behavior = terminate`
  # makes the hypervisor do the terminating. Two independent mechanisms, and the
  # one that handles the failure case is the one that cannot be denied by IAM.
  statement {
    sid       = "TerminateItself"
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/squallar-basemap-build"
      values   = ["true"]
    }
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.build.arn}:*"]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "squallar-basemap-build"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "squallar-basemap-build"
  role = aws_iam_role.instance.name
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/squallar/basemap/build"
  retention_in_days = 90
  tags              = { Name = "squallar-basemap-build" }
}

# ---------------------------------------------------------------------------
# The scheduler's role -- and the PassRole scoping, which is the sharp edge
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    # Without this, any account could name our role as the target of their own
    # schedule. The published confused-deputy guard for EventBridge Scheduler.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "squallar-basemap-scheduler"
  description        = "EventBridge Scheduler: launch the build instance, nothing else"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
  tags               = { Name = "squallar-basemap-scheduler" }
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "LaunchTheBuild"
    actions   = ["ec2:CreateFleet", "ec2:RunInstances", "ec2:CreateTags", "ec2:DescribeInstances"]
    resources = ["*"]
  }

  # THE ONE PEOPLE GET WRONG. `RunInstances` with an instance profile requires
  # `iam:PassRole`, and an unscoped PassRole is a general privilege-escalation
  # path: whoever holds it can launch a box wearing ANY role in the account.
  #
  # Scoped twice -- to the single role ARN, and to the service it may be passed
  # to. Either alone would be too wide.
  statement {
    sid       = "PassOnlyTheBuildRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.instance.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "squallar-basemap-scheduler"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
