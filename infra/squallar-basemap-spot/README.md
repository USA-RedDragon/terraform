# squallar-basemap-spot

Rebuilds the Squallar vector basemap from raw OpenStreetMap every 35 days and
publishes it to Cloudflare R2. Copied from [`../aws-spot`](../aws-spot) as a
starting point; it shares no state, no VPC and no lifecycle with it.

The bucket, its custom domain and its CORS policy are **not here** — they live
in [`../squallar/basemap.tf`](../squallar/basemap.tf). This stack only produces
and publishes the archive.

## The shape, and why it is this shape

| Layer | Owner |
|---|---|
| Launch template, IAM, SSM parameters, security group, schedules | **terraform** |
| The build instance | **nobody** |

The instance is never in terraform state. EventBridge Scheduler calls
`ec2:RunInstances` against the launch template; the instance builds, publishes,
and terminates itself. That is deliberate — an instance under management would
drift the moment it self-terminated, would need a `destroy` step, and could be
killed mid-build by an unrelated `apply`.

**There is no code to deploy for the trigger.** Scheduler's *universal target*
calls the SDK action directly (`arn:aws:scheduler:::aws-sdk:ec2:runInstances`),
so no Lambda sits between the clock and the instance. The only function here is
the heartbeat.

## Three things that carry the design

**Dead-man switch.** `shutdown -h +420` (SEVEN HOURS -- `+N` is minutes) is armed as the first act of the build
script, and the launch template sets
`instance_initiated_shutdown_behavior = terminate`. Either half alone is
useless; together, a build that hangs, deadlocks or dies before its cleanup
still costs ~$6.44 rather than costing until somebody notices. **Nothing has to
detect the hang.**

**Absence-of-artifact, not presence-of-error.** Every failure mode that matters
— spot reclaimed, box wedged, disk full, instance never launched — produces
**nothing, not an error**. So the heartbeat asks *"is there a recent archive?"*,
never *"did anything report failure?"*. It reads the public status object over
plain HTTPS and therefore needs no R2 credentials at all.

**It mails on success too.** A checker that only speaks up on failure is
indistinguishable from a checker that has died. Mailing every run — weekly —
makes silence itself the alarm. If the mail stops, something is wrong,
including the alarm.

## The cadence is 35 days, and it is a guarantee

AWS's 100 GB/month free egress resets on calendar-month boundaries. Two
*successful* builds in one month is 181 GB against that allowance — 81 GB
billable ≈ **$7.29**. One build is ~95 GB and free.

**35 exceeds the longest calendar month (31), so two builds cannot land in the
same month.** Not unlikely — impossible. It costs about 1.6 builds a year.

`rate()` and not `cron()`: rate measures from the last invocation, so the drift
is inherent, and no cron expression can say "every 35 days" at all.

**The guarantee covers the schedule, not the operator.** A manual run in the
same calendar month breaches it. Check first.

Retries are safe and do not count: a reclaimed spot instance dies during the
*download*, and inbound transfer is free. The 86 GB is paid once per
**successful** build, never per attempt.

## First apply

```sh
terraform init
terraform apply                     # schedule_state defaults to DISABLED
```

**Apply disabled the first time on purpose.** Scheduler validates the
universal-target ARN server-side at create time, so a disabled schedule is a
free, zero-risk proof that `aws-sdk:ec2:runInstances` is accepted — the one
assumption in this design verified only from a documented rule (Scheduler
publishes no allowlist, only a denylist of read-only prefixes; `runInstances`
matches none of them) rather than from a list. If it is rejected, the fallback
is a ~20-line inline Lambda and nothing else changes.

Then put the two secrets in place. **Terraform does not manage these parameters
at all** — it refers to them by a constructed ARN and never calls GetParameter.
That is deliberate: `aws_ssm_parameter` reads `value` back on every refresh and
`lifecycle { ignore_changes = [value] }` suppresses only the diff, so a managed
parameter would have written a live R2 write-credential into
`s3://mcswain-dev-tf-states` in plaintext. Creating them out of band also makes
this order-independent, since they may already exist.

```sh
umask 077; T=$(mktemp)
printf '%s' '{"access_key_id":"…","secret_access_key":"…"}' > "$T"
aws ssm put-parameter --region us-east-1 --name /squallar/basemap/r2 \
  --type SecureString --value file://"$T" --overwrite
shred -u "$T"
```

`--value file://` and not an inline argument, so the secret never enters shell
history. Same for `/squallar/basemap/smtp` (the relay key, a bare string).

Test the mail path without waiting a week:

```sh
aws lambda invoke --function-name squallar-basemap-heartbeat /dev/stdout
```

Then set `schedule_state = "ENABLED"` and apply again.

## Seeding the first archive

There is no separate bootstrap path, **and that is deliberate**. A one-off
seeding mechanism would be code that runs once and is never exercised again —
broken when it finally matters. Seeding runs the *identical* path the schedule
uses, so it is also the first real test of it:

```sh
aws ec2 create-fleet --cli-input-json "$(terraform output -raw run_now_spot)"
```

**Order matters, and only one order preserves the egress guarantee.**
`schedule_state` defaults to `DISABLED`, and `rate()` counts from when the
schedule is *enabled* — not from the apply. So:

1. Apply with `schedule_state = "DISABLED"` (the default).
2. Put both SSM secrets in place. The build reads them at boot and fails
   immediately without them.
3. Seed by hand with the command above.
4. Confirm it landed: `curl -s $(terraform output -raw status_url)`.
5. **Then** set `schedule_state = "ENABLED"` and apply.

The first scheduled build is then 35 days after step 5, necessarily in a
different calendar month from the seed. Enabling *before* seeding is the one
sequence that can put two builds in one month and cost the $7.29.

**Watching it.** Takes roughly three hours; there is no SSH by design.

```sh
aws logs tail $(terraform output -raw log_group) --follow
```

A run that fails sends mail with the last 80 log lines. A run reaped by the
dead-man switch sends nothing at all — which is exactly why the log is shipped
off the box rather than left in a file that dies with the instance.

## What happens when spot capacity is unavailable

The honest answer used to be "nothing good": one instance type in one AZ is a
**single pool**, `RunInstances` with market options fails immediately rather
than queueing, and with no retries a transient blip cost a whole 35-day cycle.

Three changes, in increasing order of how much they matter:

**Eighteen pools, not one.** Spot capacity is per *(instance type, availability
zone)*. The fleet draws from six instance types across three AZs, so "no spot
available" now means a regional shortage rather than one empty pool. This is
why the trigger is `createFleet` — `RunInstances` takes exactly one subnet and
one instance type, so it structurally cannot express it.

**24 hours of retries, made safe by a constant `ClientToken`.** CreateFleet is
idempotent on that token for 24 hours, so every retry inside the window
collapses onto the same fleet. Without it, a retry after an *ambiguous* outcome
— the call succeeded but Scheduler saw a timeout — would start a second
concurrent planet build: double compute, and two 86 GB uploads in one calendar
month.

**A manual on-demand escape hatch.** If all eighteen pools are empty for a day,
`terraform output -raw run_now_ondemand` is the identical fleet with one field
changed. ~$10 instead of ~$2.75.

**It is deliberately not automatic.** A fallback that fired on its own would
quietly quadruple the bill through a bad spot week while every build kept
succeeding — the failure nobody investigates, because nothing looks broken.

**If everything above fails, the archive just ages**, and that is survivable: a
basemap is context, not navigation, and the plan's stated policy is that an
older generation stays valid. The heartbeat reports it as stale past 40 days.
Worst case is roughly 12 days between a silently failed build and a human
finding out — which is the residual this design accepts rather than solves.

## Things that will fail late if you change them

**Do not add a 64 GiB instance type to `fleet_instance_types`.** planetiler's
own estimate against the real planet file asks for a 29 GB JVM heap *plus*
~114 GB of memory-mapped node and multipolygon cache the OS must hold.
`c6id.8xlarge` is cheaper, would widen the pool, and thrashes. Its exclusion is
deliberate. Every entry must also carry a **single** instance-store volume over
~500 GB — the build script formats one disk rather than assembling a RAID — and
must be x86_64, since the AMI filter selects an x86_64 image.

**The scratch disk must be instance store, not EBS.** Peak requirement is
~460 GB and every published planetiler benchmark runs on local NVMe.

**Do not put the heartbeat Lambda in the VPC.** It has no `vpc_config` block and
that is the most expensive line *not* in this repo: a Lambda in a VPC has no
internet route without a NAT gateway — ~$32/month, roughly ten times the cost of
the builds it watches, to send four emails a month.

**Port 25 is blocked outbound from EC2 and Lambda** and cannot be unblocked for
this. The relay is reached on 465 with implicit TLS.

**`iam:PassRole` is scoped twice** — to the single build role ARN *and* to
`iam:PassedToService = ec2.amazonaws.com`. Unscoped, it lets whoever holds it
launch an instance wearing any role in the account. Either condition alone is
too wide.

## What this does not do

- **No archive is retired.** Old generations stay in the bucket; nothing here
  deletes them. Storage is $0.015/GB-month, so two generations is ~$2.60/month
  and a lifecycle rule is a decision nobody has made yet.
- **Nothing repoints the app.** The build publishes to a versioned immutable key
  and writes the status object; moving the client to a new generation is a
  separate, deliberate act.
- **No CI runs this.** The schedule is the only automatic trigger.
