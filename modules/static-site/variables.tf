variable "domain_name" {
  description = "Primary domain. For Squallar this is a zone apex, not a subdomain -- see the CNAME-flattening note in main.tf."
  type        = string
}

variable "additional_domains" {
  description = "Extra names the certificate covers and the distribution answers for, e.g. [\"www.squallar.com\"]. Empty for the app."
  type        = list(string)
  default     = []
}

variable "bucket_name" {
  description = <<-EOT
    Origin bucket. Prefer a name that is NOT the hostname.

    S3's virtual-hosted endpoint for a dotted bucket is
    <bucket>.s3.<region>.amazonaws.com, and the wildcard certificate S3 presents
    matches exactly one label. A bucket named `squallar.app` resolves to
    squallar.app.s3.us-east-1.amazonaws.com -- two labels where the wildcard
    covers one -- so the origin handshake can fail with a 502.

    `rustdar.mcswain.dev` is dotted because it predates this module and renaming
    a bucket is a migration, not an edit. New sites take undotted names.
  EOT
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone the records are written into."
  type        = string
}

variable "cross_origin_isolation" {
  description = <<-EOT
    Whether to send COOP `same-origin` + COEP `require-corp`.

    TRUE for the app: it is what makes `crossOriginIsolated` true, which unlocks
    SharedArrayBuffer and therefore wasm threads. Without it the rayon pool
    silently collapses to one thread and the worker wire never comes up.

    FALSE for the marketing site, which ships no wasm and no worker. Setting it
    there would be cargo-culting a constraint that costs real behaviour: COEP
    `require-corp` blocks every cross-origin subresource that does not opt in,
    which is exactly the wrong default for a page that may embed third-party
    media later.
  EOT
  type        = bool
}

variable "comment" {
  description = "Human-readable label carried on the distribution and tags."
  type        = string
}

# ---------------------------------------------------------------------------
# Name overrides
#
# These exist for ONE reason: `infra/rustdar` adopted this module over
# already-applied infrastructure. Its OAC, its two policies and its origin id
# were named before the module existed, and a `moved` block re-addresses a
# resource in state without touching its attributes -- so a module that insisted
# on deriving these names would rename live resources on the adopting apply.
#
# Whether a CloudFront policy name updates in place or forces replacement is not
# a thing worth being wrong about on the origin currently serving the app, so
# the module declines to make anyone find out. New sites leave all four null and
# take the derived names.
# ---------------------------------------------------------------------------

variable "oac_name" {
  description = "Override the Origin Access Control name. Null derives it from bucket_name."
  type        = string
  default     = null
}

variable "response_headers_policy_name" {
  description = "Override the response-headers policy name. Null derives it from bucket_name."
  type        = string
  default     = null
}

variable "cache_policy_name" {
  description = "Override the cache policy name. Null derives it from bucket_name."
  type        = string
  default     = null
}

variable "origin_id" {
  description = "Override the distribution's origin id. Null derives it from bucket_name."
  type        = string
  default     = null
}
