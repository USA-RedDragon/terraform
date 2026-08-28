# ---------------------------------------------------------------------------
# The terrain build. A SECOND, PARALLEL PATH -- not a mode of the OSM build.
# ---------------------------------------------------------------------------
#
# Same shape as build.tf and for the same reasons: one launch template, no
# instance in state, no market type and no subnet on the template so CreateFleet
# owns both. What is deliberately different is that THERE IS NO SCHEDULE.
#
# The DEM does not change. Copernicus GLO-30 is a fixed release, pinned by an
# md5 of its own tileList.txt inside squallar-terrain, so a periodic rebuild
# would re-derive identical tiles from identical inputs at ~$40 a go. This runs
# when the TOOLS change, which is a human decision, and `var.terrain_tools_sha`
# is how that decision is recorded: bump the variable, apply, launch.
#
# It reuses the OSM build's IAM role, instance profile, security group, subnets
# and SSM parameters unchanged. The role's permissions are exactly right for it:
# read the same two credentials, decrypt them through SSM, terminate an instance
# tagged `squallar-basemap-build=true` (which is why the tag_specifications
# below carries that tag verbatim and not a terrain-specific one), and write
# logs. Only the log-group ARN in the Logs statement had to widen, because that
# statement is scoped to one group by ARN and this build gets its own.

# Its own group, not a second stream in the OSM group. The two jobs have very
# different lifetimes -- the terrain build is a one-shot that may run for many
# hours -- and `aws logs tail` on a shared group during a terrain run would bury
# whatever you were actually looking for.
resource "aws_cloudwatch_log_group" "terrain" {
  name              = "/squallar/basemap/terrain"
  retention_in_days = 90
  tags              = { Name = "squallar-terrain-build" }
}

resource "aws_launch_template" "terrain" {
  name        = "squallar-terrain-build"
  description = "Copernicus GLO-30 contour + hillshade build: instance-store stripe, self-terminating, human-triggered."

  # EVERY NEW VERSION BECOMES THE DEFAULT. Same reason as build.tf: a hand
  # `create-fleet` that omits the version otherwise silently gets v1.
  update_default_version = true

  image_id               = data.aws_ami.al2023.id
  vpc_security_group_ids = [aws_security_group.build.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # The other half of the dead-man switch; `shutdown -h +N` is inert without it.
  instance_initiated_shutdown_behavior = "terminate"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "squallar-terrain-build"
      # NOT a rename. This exact key/value is what the `TerminateItself`
      # condition in iam.tf matches on; a terrain-specific tag would leave the
      # box unable to kill itself, with only the dead-man switch to reap it.
      "squallar-basemap-build" = "true"
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }

  # GZIPPED, AND THAT IS A DECISION WITH A COST. STATE OF THE MEASUREMENT:
  #
  #   terrain.sh.tftpl rendered      16,240 bytes
  #   plain base64                   21,656  -- OVER the 16,384 cap by 5,272
  #   base64gzip                      9,988  -- 61% of the cap
  #
  # (measured by terraform itself against the real variable values, not by
  # base64-ing the unrendered template -- rendering grows it.)
  #
  # The bootstrap is already fetched from R2 rather than inlined (inlining its
  # 4,624 bytes would add ~6.2 KB of base64 on top), so compression is what is
  # left. cloud-init decompresses gzipped user-data before it sniffs the
  # `#!/bin/bash`, which is why this works -- BUT THAT PATH HAS NOT BEEN
  # EXECUTED HERE. If the assumption is wrong the symptom is the worst one this
  # stack has: a box that boots, runs nothing, produces no log stream, and
  # terminates on the dead-man switch with nothing to read afterwards.
  #
  # `var.terrain_smoke_filter` exists to buy that back for a few dollars. Set it
  # to a cell-name substring, launch, and the whole path proves itself against
  # one region in minutes.
  user_data = base64gzip(templatefile("${path.module}/terrain.sh.tftpl", {
    region             = data.aws_region.current.region
    log_group          = aws_cloudwatch_log_group.terrain.name
    r2_param           = local.r2_param_name
    smtp_param         = local.smtp_param_name
    r2_bucket          = var.r2_bucket
    r2_account_id      = var.r2_account_id
    archive_base_url   = var.archive_base_url
    alert_email        = var.alert_email
    alert_from         = var.alert_from
    smtp_host          = var.smtp_host
    smtp_port          = var.smtp_port
    max_build_minutes  = var.terrain_max_build_minutes
    tools_sha          = var.terrain_tools_sha
    terrain_bin_sha256 = var.terrain_bin_sha256
    bootstrap_sha256   = var.terrain_bootstrap_sha256
    raster_encoding    = var.terrain_raster_encoding
    terrain_target     = var.terrain_target
    smoke_filter       = var.terrain_smoke_filter
  }))

  tags = { Name = "squallar-terrain-build" }
}

# Mirrors `user_data_fits` in build.tf. It asserts the SAME quantity -- the
# rendered, encoded attribute EC2 will actually receive -- so it stays true
# whether or not the encoding is compressed, and it will fire if the script
# grows past what gzip can absorb.
check "terrain_user_data_fits" {
  assert {
    condition     = length(aws_launch_template.terrain.user_data) < 16384
    error_message = "Rendered terrain user-data is over EC2's 16384 base64-byte limit even gzipped. Move the tail of the script to R2 alongside bootstrap-al2023.sh."
  }
}

locals {
  terrain_fleet_overrides = flatten([
    for t in var.terrain_fleet_instance_types : [
      for az, sn in aws_subnet.build_public : {
        InstanceType = t
        SubnetId     = sn.id
      }
    ]
  ])
}
