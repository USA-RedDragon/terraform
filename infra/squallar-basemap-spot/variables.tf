variable "instance_type" {
  description = <<-EOT
    The build box. Sized from planetiler's OWN estimate against the real 98.52 GB
    planet file, printed before any work: 443 GB read-phase disk, 492 GB
    write-phase disk, 29 GB JVM heap.

    `c6id.16xlarge` is 64 vCPU / 128 GiB / 3,800 GB instance-store NVMe.

    DO NOT DROP TO A 64 GiB BOX. `c6id.8xlarge` is cheaper and was ruled out by
    the estimate: planetiler wants ~29 GB of heap PLUS ~114 GB of memory-mapped
    node and multipolygon cache that the OS has to hold. At 64 GiB it thrashes.
    128 GiB is the floor, not the target.

    The disk must be INSTANCE STORE, not EBS. Every published planetiler
    benchmark runs its scratch on local NVMe, and the ~460 GB peak would be both
    slow and expensive on a network volume.
  EOT
  type        = string
  default     = "c6id.16xlarge"
}

variable "spot_max_price" {
  description = <<-EOT
    Empty string means "pay up to the on-demand price", which is the right
    default: a cap below the on-demand rate buys nothing here except the
    possibility of not launching at all.

    Interruption is survivable BECAUSE THE BUILD IS STATELESS -- download, build,
    upload, terminate, no cache and no cross-run state. planetiler cannot
    checkpoint (`--reuse_featuredb` needs a 278 GB feature DB that dies with the
    instance store), so there is nothing an interruption could have saved. A
    reclaimed run is simply re-run.

    And a reclaimed attempt costs no egress: it dies during the DOWNLOAD, and
    inbound transfer is free and unmetered. The 86 GB is paid once per
    SUCCESSFUL build, never per attempt.
  EOT
  type        = string
  default     = ""
}

variable "build_schedule" {
  description = <<-EOT
    EVERY 35 DAYS, AND THE NUMBER IS A GUARANTEE RATHER THAN A BUFFER.

    AWS's 100 GB/month free egress allowance resets on calendar-month
    boundaries. Two SUCCESSFUL builds in one calendar month is 2 x 86 GB plus
    ~9 GB of existing account traffic = 181 GB, so 81 GB billable at $0.09 =
    ~$7.29. One build is ~95 GB and free.

    A minimum gap of 35 days EXCEEDS THE LONGEST CALENDAR MONTH (31), so two
    builds cannot fall in the same month. Not unlikely -- impossible. It costs
    about 1.6 builds a year against monthly.

    `rate()` and not `cron()`: rate measures from the LAST INVOCATION, so the
    drift through the calendar is inherent. No cron expression can say "every 35
    days" at all.

    THE GUARANTEE COVERS THE SCHEDULE, NOT THE OPERATOR. A manual run in the same
    calendar month as a scheduled one breaches it. Check the month first.
  EOT
  type        = string
  default     = "rate(35 days)"
}

variable "max_build_minutes" {
  description = <<-EOT
    Dead-man switch. The instance runs `shutdown -h +N` at boot, and the launch
    template sets `instance_initiated_shutdown_behavior = terminate`, so the box
    dies on its own even if the build script hangs, deadlocks, or exits without
    reaching its cleanup.

    MINUTES, not seconds -- `shutdown -h +N` takes minutes. 420 is seven hours.

    Sized from an asymmetry rather than from the estimate, because the estimate
    is soft: expected run is ~2.5-3h (94.5 GB PBF download, 60-90 min build on
    64 vCPU, 86 GB upload), but EVERY published planetiler benchmark is on a
    SMALLER input than ours -- 69-92 GB against 94.5 -- so there is no measured
    number for the run we actually make.

    The two ways to be wrong cost very different amounts:

      too TIGHT  -> kills a WORKING build. ~$2.75 wasted, plus either a manual
                    re-run or 35 days of staleness.
      too LOOSE  -> $0.92/hr on a box that is already wedged.

    So buy headroom. 420 gives ~2.4x on the estimate for at most $1.84 more
    than 300 would have cost in the wedged case. An earlier draft used 300 --
    1.7x -- which is too tight to absorb a slow spot box or a bigger planet.

    TIGHTEN THIS ONCE THERE IS A REAL MEASUREMENT. The first build produces the
    only number that matters, and this should then be set from it rather than
    from a benchmark on someone else's input.

    This is the difference between a failure mode being removed and being
    handled. Nothing has to detect the hang.
  EOT
  type        = number
  default     = 420
}

variable "alert_email" {
  description = <<-EOT
    Where the heartbeat, the build-success mail and the staleness alarm are sent.

    THIS IS THE ONLY SIGNAL THAT A BUILD STOPPED WORKING. Every failure mode
    that matters produces no error anywhere -- it produces nothing -- so if this
    address is not one somebody actually reads, the whole alarm design is
    decorative. It is a deliberate choice, not a default to inherit.
  EOT
  type        = string
  default     = "squallar-basemap@mcswain.dev"
}

variable "alert_from" {
  description = <<-EOT
    The `From:` address. A VARIABLE because it was previously hardcoded in two
    places -- the build script and the heartbeat function -- which is exactly
    how the two drift apart.

    It must be an address the relay will sign for. An earlier version built it
    from the SMTP hostname (`squallar-basemap@email.mcswain.dev`), which is the
    relay's own host rather than the sending domain, and would have been at the
    mercy of however SPF/DKIM is configured for it. **A heartbeat that lands in
    spam is a heartbeat you stop noticing**, which is the same failure as not
    sending one.
  EOT
  type        = string
  default     = "squallar-basemap-alerts@mcswain.dev"
}

variable "smtp_host" {
  description = <<-EOT
    Implicit TLS on 465, NOT 25. Port 25 is blocked outbound from EC2 and Lambda
    by default and cannot be unblocked on request for this kind of workload.
  EOT
  type        = string
  default     = "email.mcswain.dev"
}

variable "smtp_port" {
  description = "465, implicit TLS. See `smtp_host`."
  type        = number
  default     = 465
}

variable "archive_base_url" {
  description = <<-EOT
    Public read origin for the archive, from `infra/squallar`'s
    `cloudflare_r2_custom_domain`. The staleness check reads
    `<archive_base_url>/status/latest.json` over plain HTTPS, which is why the alarm needs
    NO R2 credentials at all.
  EOT
  type        = string
  default     = "https://tiles.squallar.app"
}

variable "r2_bucket" {
  description = "R2 bucket the build publishes into. Declared in infra/squallar."
  type        = string
  default     = "squallar-basemap"
}

variable "r2_account_id" {
  description = "Cloudflare account id, for the S3-compatible endpoint host."
  type        = string
  default     = "66c3a6ef76da199efb7221569ebc5781"
}

variable "planetiler_version" {
  description = <<-EOT
    Pinned, not `latest`. The build is the one input to the published archive
    that could otherwise change without a commit here, and a schema or
    simplification change arriving silently would be indistinguishable from an
    upstream OSM change.
  EOT
  type        = string
  default     = "0.10.2"
}

variable "schedule_state" {
  description = <<-EOT
    ENABLED or DISABLED.

    Apply the FIRST time with DISABLED. EventBridge Scheduler validates the
    universal-target ARN server-side at create time, so a disabled schedule is
    a free, zero-risk proof that `aws-sdk:ec2:runInstances` is accepted -- the
    one unverified assumption in this design -- without launching a $2.75
    three-hour build to find out.

    Then flip to ENABLED.
  EOT
  type        = string
  default     = "DISABLED"
}

variable "stale_after_days" {
  description = <<-EOT
    Longer than the 35-day build cadence on purpose, so an archive is never
    reported stale merely for being due. 40 gives five days of slack for a
    build that ran late or was re-run after a spot reclamation.
  EOT
  type        = number
  default     = 40
}

variable "fleet_instance_types" {
  description = <<-EOT
    The pools the fleet may draw from. Combined with three AZs this is EIGHTEEN
    (type, zone) pools rather than one, which is the difference between "spot is
    unavailable" meaning a single empty pool and meaning a regional shortage.

    EVERY ENTRY MUST SATISFY THREE HARD CONSTRAINTS, and a violation shows up as
    a build that starts and then fails hours in:

      1. >= 128 GiB RAM. planetiler's own estimate wants a 29 GB JVM heap PLUS
         ~114 GB of memory-mapped node/multipolygon cache the OS must hold. The
         64 GiB shapes (c6id.8xlarge and friends) thrash and are excluded on
         purpose, not overlooked.
      2. Instance-store NVMe, with a SINGLE volume >= ~500 GB. Peak requirement
         is ~460 GB. The build script formats ONE disk rather than assembling a
         RAID, so what matters is the size of the largest single volume, not the
         instance's total.
      3. x86_64. The AMI filter in build.tf selects an x86_64 image; adding a
         Graviton type here without changing that gives an architecture mismatch
         at launch.

    Ordered roughly cheapest-first, though `price-capacity-optimized` allocation
    means the fleet weighs interruption risk as well as price and may not take
    the first.
  EOT
  type        = list(string)
  default = [
    "c6id.16xlarge", # 64 vCPU, 128 GiB, 2x1900 GB
    "m6id.8xlarge",  # 32 vCPU, 128 GiB, 1x1900 GB
    "m6id.12xlarge", # 48 vCPU, 192 GiB, 2x1425 GB
    "c6id.24xlarge", # 96 vCPU, 192 GiB, 4x1425 GB
    "m6id.16xlarge", # 64 vCPU, 256 GiB, 2x1900 GB
    "r6id.8xlarge",  # 32 vCPU, 256 GiB, 1x1900 GB
  ]
}
