# squallar

Two static sites behind CloudFront, sharing one deploy role:

| | Origin bucket | Isolated | Serves |
|---|---|---|---|
| `squallar.app` | `squallar-app-origin` | yes | the PWA |
| `squallar.com` + `www.` | `squallar-com-origin` | no | the marketing site |

Both come from [`modules/static-site`](../../modules/static-site). The module
lives at the repo root rather than under `infra/` because the terraform workflow
runs with `working-directory: infra`, and a directory of `.tf` files with no
backend sitting inside that path is an invitation for the plan to try to
initialise it.
