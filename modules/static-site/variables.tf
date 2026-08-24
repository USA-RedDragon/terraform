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
    Origin bucket. Deliberately NOT the hostname here, unlike the rustdar module.

    S3's virtual-hosted endpoint for a dotted bucket is
    <bucket>.s3.<region>.amazonaws.com, and the wildcard certificate S3 presents
    matches exactly one label. A bucket literally named `squallar.app` resolves
    to squallar.app.s3.us-east-1.amazonaws.com -- two labels where the wildcard
    covers one -- so the origin handshake can fail with a 502. The rustdar
    module carries a dotted name and documents this as "one eye open at first
    apply"; these buckets are new, so there is no reason to inherit the hazard.
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
