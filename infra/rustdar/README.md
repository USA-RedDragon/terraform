# rustdar

Hosting for the rustdar PWA at `https://rustdar.mcswain.dev`: a private S3
bucket, a CloudFront distribution in front of it, an ACM certificate, the
Cloudflare DNS records, and the GitHub OIDC role the app repo deploys with.

## Why it is not on GitHub Pages

The app is a wasm PWA that wants `SharedArrayBuffer` and wasm threads, and the
browser only hands those to a cross-origin isolated document. Isolation needs
two response headers -- `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` -- which Pages does not let you
set. That is the whole reason for this module; the distribution's response
headers policy is the payload and everything else is scaffolding around it.

The isolated configuration was proven before this was written: the browser rig
ran the full gate under COOP/COEP on Chromium and Firefox, 4/4 pass, with
`crossOriginIsolated` genuinely true, the service worker registering and taking
control, and no cross-origin request blocked across ten origins.

## Two behaviours the service worker depends on

Both are encoded in `cloudfront.tf` and commented there; repeated here because
breaking either one fails quietly rather than loudly.

1. **`HEAD` is allowed and `ETag` / `Last-Modified` reach the viewer.** `sw.js`
   discovers deploys by HEADing `pkg/rustdar_web_bg.wasm` and the directory
   index with `cache: "no-store"` and folding the returned validators into a
   shell-version token. Strip the validators, or answer HEAD with a 405, and the
   worker concludes nothing has changed -- permanently. Nothing here removes
   response headers, and the behaviour allows `GET, HEAD`.
2. **Nothing is long-cached, because nothing is content-hashed.** The deployed
   names are fixed (`pkg/rustdar_web.js`, `pkg/rustdar_web_bg.wasm`,
   `worker.js`, `sw.js`, the icons), which is precisely what makes the validator
   probe above work. Viewers get
   `Cache-Control: public, max-age=0, must-revalidate` on every path; the edge
   holds objects for 5 minutes and the deploy invalidates. If the web build ever
   emits hashed filenames, that is the moment to add an `ordered_cache_behavior`
   for them with a long `immutable` max-age -- and it must carry the same
   `response_headers_policy_id`, or service worker registration breaks.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.63.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 5.24.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.24.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_site"></a> [site](#module\_site) | ../../modules/static-site | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_zone.mcswain_dev](https://registry.terraform.io/providers/cloudflare/cloudflare/5.24.0/docs/data-sources/zone) | data source |

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Origin bucket; the deploy step's `aws s3 sync` target. |
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | CloudFront domain name the rustdar CNAME points at. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | CloudFront distribution id; the deploy step's `aws cloudfront create-invalidation --distribution-id`. |
| <a name="output_site_url"></a> [site\_url](#output\_site\_url) | Public URL of the tombstone that retired this origin. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
