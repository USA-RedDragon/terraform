# Nothing consumes these programmatically -- the schedule launches the build and
# the build publishes itself. They exist so the two identifiers you need in
# order to run or debug a build by hand are readable from state.

output "launch_template_id" {
  description = <<-EOT
    Run a build by hand:

      see the run_now_spot output for a ready-to-run create-fleet payload

    CHECK THE CALENDAR MONTH FIRST. The 35-day cadence guarantees at most one
    build per month; a manual run alongside a scheduled one breaches it and
    costs ~$7.29 in egress.
  EOT
  value       = aws_launch_template.build.id
}

output "log_group" {
  description = "Where the build's console output lands. There is no SSH into the box by design."
  value       = aws_cloudwatch_log_group.build.name
}

output "status_url" {
  description = <<-EOT
    The build's own record of what it published, written LAST and only after the
    archive verifies through the public path. Readable with no credentials:

      curl -s <this> | python3 -m json.tool
  EOT
  value       = "${var.archive_base_url}/status/latest.json"
}

output "heartbeat_function" {
  description = "Invoke it to test the mail path without waiting a week: aws lambda invoke --function-name <this> /dev/stdout"
  value       = aws_lambda_function.heartbeat.function_name
}

output "run_now_spot" {
  description = <<-EOT
    Seed the first archive, or re-run after a failure. Same 18 pools the
    schedule uses, so this exercises the real path rather than a bootstrap path
    that only runs once:

      aws ec2 create-fleet --cli-input-json "$(terraform output -raw run_now_spot)"

    CHECK THE CALENDAR MONTH FIRST. The 35-day cadence guarantees at most one
    build per month; a manual run alongside a scheduled one costs ~$7.29 in
    egress.
  EOT
  value = jsonencode({
    Type                        = "instant"
    TargetCapacitySpecification = { TotalTargetCapacity = 1, DefaultTargetCapacityType = "spot" }
    SpotOptions                 = { AllocationStrategy = "price-capacity-optimized" }
    LaunchTemplateConfigs = [{
      LaunchTemplateSpecification = { LaunchTemplateId = aws_launch_template.build.id, Version = "$Latest" }
      Overrides                   = local.fleet_overrides
    }]
  })
}

output "run_now_ondemand" {
  description = <<-EOT
    The escape hatch, for when all eighteen spot pools are empty. Identical
    except for one field -- `DefaultTargetCapacityType` -- so there is no second
    template, no second script and no second code path to rot:

      aws ec2 create-fleet --cli-input-json "$(terraform output -raw run_now_ondemand)"

    ~$3.23/hr against spot's ~$0.92, so about $10 a build instead of $2.75.
    Paying $7 to stop waiting is obviously right on the rare occasion it comes
    up.

    DELIBERATELY NOT AUTOMATIC. A fallback that fired on its own would quietly
    quadruple the bill during a bad spot week while every build kept succeeding
    -- the failure nobody investigates because nothing looks broken.
  EOT
  value = jsonencode({
    Type                        = "instant"
    TargetCapacitySpecification = { TotalTargetCapacity = 1, DefaultTargetCapacityType = "on-demand" }
    LaunchTemplateConfigs = [{
      LaunchTemplateSpecification = { LaunchTemplateId = aws_launch_template.build.id, Version = "$Latest" }
      Overrides                   = local.fleet_overrides
    }]
  })
}

output "spot_pools" {
  description = "How many (instance type, availability zone) pools the fleet may draw from. One was fragile; this is the number that makes 'no spot available' mean a regional shortage."
  value       = length(local.fleet_overrides)
}
