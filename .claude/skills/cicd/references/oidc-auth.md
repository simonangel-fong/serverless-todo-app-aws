# OIDC authentication (no static keys)

The highest-value change to any AWS deploy pipeline: stop storing long-lived
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` in GitHub secrets. Instead, GitHub
issues a short-lived OIDC token per run, AWS trusts it via an OIDC provider, and
the workflow assumes a role scoped to this repo. Nothing long-lived lives in CI.

## The two halves

OIDC has an AWS side and a workflow side; they must agree.

**AWS side** (Terraform, see the terraform-wf skill / your `oidc.tf`):
- an IAM OIDC provider for `token.actions.githubusercontent.com`
- a deploy role whose trust policy allows
  `sts:AssumeRoleWithWebIdentity` when the token's `sub` matches this repo/ref and
  `aud` is `sts.amazonaws.com`.

**Workflow side** (this skill):
- `permissions: id-token: write` on the job
- `aws-actions/configure-aws-credentials` with `role-to-assume`.

## Workflow configuration

```yaml
permissions:
  id-token: write   # REQUIRED — lets the job request the OIDC token
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
          # No aws-access-key-id / aws-secret-access-key — that's the point.
```

`role-to-assume` is the `deploy_role_arn` Terraform output. Store it as a secret
(or a repo variable — it's not sensitive, but a secret keeps the account id out of
logs). After this step, all AWS CLI / Terraform AWS calls in the job use the
assumed role's temporary credentials automatically.

## Why the permission matters

`id-token: write` is what lets the runner request the OIDC JWT. Without it,
`configure-aws-credentials` fails with a confusing "Could not load credentials"
or "Unable to get OIDC token" error even though the role and trust policy are
correct. It's the single most common OIDC setup mistake.

## How trust scoping pairs with triggers

The role's trust policy `sub` condition decides *which refs* can assume it — and
it must cover every ref the workflow runs apply/plan from. Common shapes:

- `repo:OWNER/REPO:ref:refs/heads/main` — only the default branch (apply).
- `repo:OWNER/REPO:pull_request` — PR runs (plan).
- `repo:OWNER/REPO:environment:prod` — only when the job targets a named
  environment (tightest; pairs with an approval gate).

If PRs need to plan but only main should apply, the trust policy must allow both
the `pull_request` and the `ref:refs/heads/main` subs, and the *workflow* gating
(next reference) is what actually restricts apply to main. Trust scoping and
workflow `if:` conditions are two independent layers — use both.

## Multi-provider note

If the Terraform also manages a non-AWS provider (e.g. Cloudflare DNS), OIDC
covers only AWS. That provider's credential (an API token) still has to be passed
in — as a GitHub secret via its `TF_VAR_...` env var. OIDC doesn't eliminate it;
it only eliminates the *AWS* keys. Keep that token as the sole long-lived secret
and scope it minimally.
