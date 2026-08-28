# Amazon Linux 2023: `aws` CLI v2 is preinstalled, dnf has a current Corretto,
# and the kernel names instance-store volumes in a way `lsblk -o MODEL` can find.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.*-x86_64"]
  }
}

# The build box, as a TEMPLATE and not an instance.
#
# Nothing in this stack ever creates an instance. The scheduler calls
# `ec2:RunInstances` against this template, and the instance terminates itself.
# That is deliberate: an instance under terraform management would drift the
# moment it self-terminated, would need a `destroy` step, and could be killed
# mid-build by an unrelated `apply`. Terraform owns everything durable; the
# ephemeral thing is owned by nobody.
# ONE launch template, and it deliberately specifies NEITHER a market type NOR a
# subnet.
#
# Both omissions are required rather than stylistic. `CreateFleet` REJECTS a
# launch template that carries `InstanceMarketOptions` -- the fleet owns that
# decision -- and the subnet has to come from the fleet's per-pool overrides,
# because the whole point is trying several. So security groups attach via
# `vpc_security_group_ids` rather than a `network_interfaces` block, which is
# the form that leaves the subnet free.
#
# The same template serves the scheduled spot fleet and the manual on-demand
# fallback. One definition, one user-data script, one role -- the market choice
# lives entirely in the CreateFleet call.
resource "aws_launch_template" "build" {
  name        = "squallar-basemap-build"
  description = "Planet basemap build: instance-store scratch, self-terminating. Market chosen by the fleet."

  image_id               = data.aws_ami.al2023.id
  vpc_security_group_ids = [aws_security_group.build.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # THE OTHER HALF OF THE DEAD-MAN SWITCH.
  # `shutdown -h +N` in the script is inert without this: the default is `stop`,
  # which would leave a stopped instance sitting there indefinitely.
  instance_initiated_shutdown_behavior = "terminate"

  # The tag the self-terminate IAM condition matches on. Without it the instance
  # cannot kill itself and only the dead-man switch reaps it.
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                     = "squallar-basemap-build"
      "squallar-basemap-build" = "true"
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }

  user_data = base64encode(templatefile("${path.module}/build.sh.tftpl", {
    region             = data.aws_region.current.region
    log_group          = aws_cloudwatch_log_group.build.name
    r2_param           = local.r2_param_name
    smtp_param         = local.smtp_param_name
    r2_bucket          = var.r2_bucket
    r2_account_id      = var.r2_account_id
    archive_base_url   = var.archive_base_url
    alert_email        = var.alert_email
    alert_from         = var.alert_from
    smtp_host          = var.smtp_host
    smtp_port          = var.smtp_port
    max_build_minutes  = var.max_build_minutes
    planetiler_version = var.planetiler_version
  }))

  tags = { Name = "squallar-basemap-build" }
}

# user-data is capped at 16 KiB AFTER base64, and the script is close enough to
# be worth asserting rather than discovering on a failed launch -- where the
# symptom is an instance that boots and does nothing at all.
check "user_data_fits" {
  assert {
    condition     = length(aws_launch_template.build.user_data) < 16384
    error_message = "Rendered user-data is over EC2's 16384 base64-byte limit. Move the script to S3 and bootstrap it."
  }
}

# The pool set the fleet chooses from, as one value both the schedule and the
# manual fallback read.
locals {
  fleet_overrides = flatten([
    for t in var.fleet_instance_types : [
      for az, sn in aws_subnet.build_public : {
        InstanceType = t
        SubnetId     = sn.id
      }
    ]
  ])
}
