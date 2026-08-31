variable "github_repo" {
  description = <<-EOT
    The GitHub OIDC subject the deploy role trusts, as it appears between
    `repo:` and the trailing `:*`.

    THIS IS THE IMMUTABLE FORM, NOT `owner/name`. GitHub gives repositories
    created after 2026-07-15 a subject built from numeric ids that no rename can
    change:

        repo:OWNER@OWNER-ID/REPO@REPO-ID:ref:refs/heads/BRANCH

    This repository was created 2026-08-24, so that is what its tokens carry.
    Read the live value from Settings -> Actions -> "Default subject claim
    prefix", or from any failing job's OIDC token -- do not assemble it by hand.

    CONFIRM THIS BEFORE THE FIRST APPLY. It is the one value here that fails
    late and confusingly: a wrong subject applies cleanly, and then every deploy
    dies at `configure-aws-credentials` with "Not authorized to perform
    sts:AssumeRoleWithWebIdentity" -- which reads like a broken role, not a
    typo'd repository name. It did exactly that on 2026-08-31: the old
    `owner/name` form was applied and the cutover deploy died twelve retries
    deep. Note that `StringLike` is case-sensitive, so `squallar/squallar`
    would have missed on the owner's capital S even in the legacy format --
    two independent reasons for the same silent failure.
  EOT
  type        = string
  default     = "Squallar@320083733/squallar@1344589140"
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

    R2 matches these exactly -- there is no wildcard form short of `*`.

    **The cost argument that used to live here was wrong, and is retracted
    rather than reworded.** It claimed `*` would let any page stream our
    egress and bill Class B operations. MEASURED 2026-08-28: CORS is enforced
    browser-side AFTER delivery -- a hotlinking page's range requests reach
    the edge and bill Class B ops whether or not its origin is allowed; the
    header only decides if that page's JS may read the body. Restricting
    origins buys hotlink FRICTION, nothing more. The list below is that
    friction, chosen deliberately (decision 2026-08-29).

    `*` -- decided 2026-08-29, forgoing hotlink friction entirely. What it
    buys: local dev on any port, the browser rig's random per-run ports, and
    any future preview deploy all draw the basemap with no terraform edit.
    What it forgoes is only the friction named above; the request cost was
    identical either way.

    Native builds are unaffected -- CORS is a browser mechanism and the desktop
    and mobile HTTP stacks never consult it.
  EOT
  type        = list(string)
  default     = ["*"]
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
