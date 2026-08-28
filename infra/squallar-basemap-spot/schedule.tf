# ---------------------------------------------------------------------------
# The trigger. No Lambda, no code, no workflow.
# ---------------------------------------------------------------------------
#
# EventBridge Scheduler's UNIVERSAL TARGET calls an AWS SDK action directly:
# `arn:aws:scheduler:::aws-sdk:{service}:{apiAction}`, camelCase action.
#
# `runInstances` is supported, and the evidence is a rule rather than a list:
# Scheduler publishes no allowlist, only a DENYLIST OF READ-ONLY PREFIXES
# (get, describe, list, poll, receive, search, scan, query, select, read,
# lookup, discover, validate, batchGet, ...). `runInstances` matches none.
#
# Verify on first apply the cheap way: create it with `state = DISABLED`, which
# validates the target ARN server-side without ever firing, then enable it.
resource "aws_scheduler_schedule" "build" {
  name        = "squallar-basemap-build"
  description = "Planet basemap rebuild, every 35 days. See var.build_schedule for why 35."
  group_name  = "default"

  schedule_expression          = var.build_schedule
  schedule_expression_timezone = "UTC"
  state                        = var.schedule_state

  # OFF, not a window. A flexible window would let two builds drift closer
  # together than 35 days, which is exactly the property the cadence buys.
  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:createFleet"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      # `instant` returns synchronously with instances or with errors, which is
      # what makes this usable from a scheduler: the alternatives leave a
      # long-lived fleet request behind that would need reaping.
      Type = "instant"

      TargetCapacitySpecification = {
        TotalTargetCapacity       = 1
        DefaultTargetCapacityType = "spot"
      }

      SpotOptions = {
        # Weighs price AND the depth of each pool, so it avoids the cheapest
        # pool when that pool is nearly empty. For a single instance that runs
        # for hours, not being interrupted is worth more than a few cents.
        AllocationStrategy = "price-capacity-optimized"
      }

      LaunchTemplateConfigs = [{
        LaunchTemplateSpecification = {
          LaunchTemplateId = aws_launch_template.build.id
          Version          = "$Latest"
        }
        # 18 (type, subnet) pools. See var.fleet_instance_types.
        Overrides = local.fleet_overrides
      }]

      # A CONSTANT ClientToken, AND THE CONSTANCY IS THE ENTIRE MECHANISM.
      #
      # CreateFleet is idempotent on ClientToken FOR 24 HOURS. A fixed token
      # means every retry inside that window collapses onto the same fleet, and
      # the next scheduled run 35 days later is unaffected because the token has
      # long expired.
      #
      # That is what makes the retry policy below safe. Without it, a retry
      # after an AMBIGUOUS outcome -- the call succeeded but Scheduler saw a
      # timeout -- would start a SECOND concurrent planet build: double the
      # compute, and two 86 GB uploads in one calendar month, which is the
      # $7.29 egress case the 35-day cadence exists to prevent.
      #
      # Scheduler's universal target sends STATIC json, so a per-invocation
      # token is not expressible even if we wanted one. Here the constraint
      # hands us exactly the semantics we need.
      ClientToken = "squallar-basemap-scheduled-build"
    })

    # 24 hours of retries, matched deliberately to the ClientToken idempotency
    # window so the two cannot disagree: every attempt inside the window is the
    # same fleet, and once the window closes there are no attempts left.
    #
    # Retries matter less now than they did with RunInstances -- an 18-pool
    # fleet rarely finds nothing -- but a regional shortage or an API throttle
    # is still transient, and waiting 35 days for the next cycle is not a
    # proportionate response to either.
    retry_policy {
      maximum_event_age_in_seconds = 86400
      maximum_retry_attempts       = 185
    }
  }
}

# ---------------------------------------------------------------------------
# The heartbeat. This is the part going unattended actually costs.
# ---------------------------------------------------------------------------

data "archive_file" "heartbeat" {
  type        = "zip"
  source_file = "${path.module}/lambda/heartbeat.py"
  output_path = "${path.module}/.heartbeat.zip"
}

data "aws_iam_policy_document" "heartbeat_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "heartbeat" {
  name               = "squallar-basemap-heartbeat"
  description        = "Reads the public status object, reads the SMTP key, mails"
  assume_role_policy = data.aws_iam_policy_document.heartbeat_assume.json
}

data "aws_iam_policy_document" "heartbeat" {
  statement {
    sid       = "ReadSmtpKey"
    actions   = ["ssm:GetParameter"]
    resources = [local.smtp_param_arn]
  }
  statement {
    sid       = "DecryptIt"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "heartbeat" {
  name   = "squallar-basemap-heartbeat"
  role   = aws_iam_role.heartbeat.id
  policy = data.aws_iam_policy_document.heartbeat.json
}

# NOTE THE ABSENCE OF A `vpc_config` BLOCK, AND IT IS THE MOST EXPENSIVE LINE
# NOT IN THIS FILE.
#
# A Lambda placed in a VPC has NO internet route without a NAT gateway --
# ~$32/month plus per-GB processing, roughly TEN TIMES the entire cost of the
# builds it watches, to send four emails a month. Outside a VPC it gets outbound
# internet for free, and it needs nothing private: the status object is public
# HTTPS and the relay is on the internet.
resource "aws_lambda_function" "heartbeat" {
  function_name = "squallar-basemap-heartbeat"
  description   = "Absence-of-artifact check for the basemap archive; mails on both outcomes"
  role          = aws_iam_role.heartbeat.arn
  handler       = "heartbeat.handler"
  runtime       = "python3.13"
  timeout       = 60

  filename         = data.archive_file.heartbeat.output_path
  source_code_hash = data.archive_file.heartbeat.output_base64sha256

  environment {
    variables = {
      ARCHIVE_BASE_URL = var.archive_base_url
      SMTP_PARAM       = local.smtp_param_name
      SMTP_HOST        = var.smtp_host
      SMTP_PORT        = tostring(var.smtp_port)
      ALERT_EMAIL      = var.alert_email
      ALERT_FROM       = var.alert_from
      STALE_AFTER_DAYS = tostring(var.stale_after_days)
    }
  }
}

data "aws_iam_policy_document" "heartbeat_scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "heartbeat_scheduler" {
  name               = "squallar-basemap-heartbeat-scheduler"
  assume_role_policy = data.aws_iam_policy_document.heartbeat_scheduler_assume.json
}

resource "aws_iam_role_policy" "heartbeat_scheduler" {
  name = "squallar-basemap-heartbeat-scheduler"
  role = aws_iam_role.heartbeat_scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.heartbeat.arn
    }]
  })
}

# WEEKLY, not every 35 days, and the reason is detection latency.
#
# At `rate(35 days)` a failed build would go unnoticed for up to 35 days, and a
# heartbeat that silent is not a heartbeat -- you cannot tell "quiet because
# healthy" from "quiet because dead". Weekly means a failure surfaces within 7
# days and a missing mail is conspicuous. Lambda invocations at this volume are
# free.
#
# The 40-day staleness threshold is deliberately LONGER than the 35-day build
# cadence, so a healthy archive is never reported stale merely for being due.
resource "aws_scheduler_schedule" "heartbeat" {
  name        = "squallar-basemap-heartbeat"
  description = "Weekly: is there a recent archive? Mails either way."
  group_name  = "default"

  schedule_expression          = "rate(7 days)"
  schedule_expression_timezone = "UTC"
  state                        = var.schedule_state

  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 60
  }

  target {
    arn      = aws_lambda_function.heartbeat.arn
    role_arn = aws_iam_role.heartbeat_scheduler.arn
  }
}
