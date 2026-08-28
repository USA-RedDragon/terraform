variable "github_repo" {
  description = <<-EOT
    The `owner/name` the release workflow runs in, used as the GitHub OIDC
    subject the deploy role trusts.

    CONFIRM THIS BEFORE THE FIRST APPLY. It is the one value here that fails
    late and confusingly: a wrong subject applies cleanly, and then every deploy
    dies at `configure-aws-credentials` with "Not authorized to perform
    sts:AssumeRoleWithWebIdentity" -- which reads like a broken role, not a
    typo'd repository name.

    The default assumes the repository keeps its name inside the new org. If it
    is renamed on the way over -- `squallar/app`, `squallar/radar` -- set this.
  EOT
  type        = string
  default     = "squallar/squallar"
}

variable "basemap_domain" {
  description = <<-EOT
    Hostname the basemap archive is served from. A subdomain of squallar.app so
    that it binds into a zone this stack already reads, and so that the archive
    and the app that reads it cannot end up on different registrable domains.

    Changing this is not free on the client side: the app compiles the archive
    URL in, and an old build keeps asking for the old name. Treat a rename as a
    migration with an overlap period, not as an edit.
  EOT
  type        = string
  default     = "tiles.squallar.app"
}

variable "basemap_cors_origins" {
  description = <<-EOT
    Origins allowed to read the basemap archive from a browser.

    Production only by default. R2 matches these exactly -- there is no wildcard
    form short of `*` -- so a local dev server cannot be covered by a pattern
    and `*` is not the answer either: it would let any page on the internet
    stream our egress, and while egress is $0 the Class B operations are not.

    LOCAL WEB DEVELOPMENT therefore needs its origin added here temporarily.
    There is no fixed port to pre-authorise: the browser rig picks one per run
    (`.github/browser-rig/run_tier2.sh` serves on `127.0.0.1:$PORT`), so a
    hardcoded `http://localhost:8080` would be a guess that works by luck.

    Native builds are unaffected -- CORS is a browser mechanism and the desktop
    and mobile HTTP stacks never consult it.
  EOT
  type        = list(string)
  default     = ["https://squallar.app"]
}

variable "basemap_ratelimit_per_minute" {
  description = <<-EOT
    Per-IP requests per 60 s on the archive prefixes before a 10 s block.

    Sized COST-FIRST: the value is what one hostile IP may bill, not what a
    legitimate user might need. 6,000 admits $3.11/day/IP in R2 Class B ops
    and clears a single-pane flat-out panner (3,240/min) by 1.85x; a two-pane
    flat-out panner trips it and waits sixty seconds. The full derivation, and
    why the first draft's 50,000 ($777/month/IP) was backwards, is at the
    ruleset in basemap_edge.tf.
  EOT
  type        = number
  default     = 6000
}
