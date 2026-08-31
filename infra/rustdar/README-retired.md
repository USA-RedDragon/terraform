# rustdar.mcswain.dev — retired 2026-08-31

This stack no longer deploys anything. Squallar moved to `squallar.app`
(`../squallar`), and what is left here serves a **tombstone**: a redirect page
and a service worker at `/sw.js` that unregisters the app's old worker and sends
installed clients to the new origin.

Those two files were published by `deploy-tombstone` in the app repository's
`build.yaml`. **That job and its IAM role are gone**, so this stack can no
longer be written to by CI. That is deliberate: the tombstone is permanent, it
never needs updating, and a role with write access to a live origin that nothing
legitimately uses is a standing risk, not a convenience.

## What remains, and why none of it can go

Every remaining resource is the redirect itself:

| resource | why it stays |
|---|---|
| S3 bucket (+ policy, ownership, encryption, public-access block) | holds the two tombstone files |
| CloudFront distribution + origin access control | serves them over HTTPS at this hostname |
| cache policy, response-headers policy | referenced by the distribution |
| ACM certificate + validation | the `rustdar.mcswain.dev` alias needs a valid cert |
| Cloudflare DNS records (site + ACM validation) | resolve the hostname, keep the cert renewing |

Cost is effectively nil: CloudFront has no fixed monthly charge, two small
objects in S3 are pennies, ACM is free and the Cloudflare records are on the
free tier.

## To re-publish or change the tombstone

Nothing here can write to the bucket any more. Restore `iam.tf` from git history
(`git log -- infra/rustdar/iam.tf`), apply, re-add the deploy job, publish, then
remove them again — or sync the two files by hand with an admin credential.

## To take the origin down entirely

`terraform destroy` this stack. `rustdar.mcswain.dev` then stops resolving, and
anyone still holding the old PWA keeps a frozen shell with no way to be told it
moved. Only do that once the tombstone has been up long enough to have done its
work.
