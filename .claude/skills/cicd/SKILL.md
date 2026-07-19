---
name: cicd
description: >-
  Author and refactor GitHub Actions pipelines that deploy Terraform + AWS
  (serverless stacks especially: Lambda packaging, static-site sync to S3 +
  CloudFront). Use this whenever you are writing or fixing a deploy workflow,
  moving a pipeline from static AWS keys to GitHub OIDC, adding plan/apply
  gating, wiring an approval gate, packaging a Lambda from source, injecting
  Terraform outputs into a frontend before syncing, or invalidating a CloudFront
  distribution. Trigger even when the user just says "fix the pipeline", "the
  deploy workflow is a mess", "use OIDC instead of keys", "the CI is deploying on
  PRs", "add an apply approval", or mentions deploy.yml, GitHub Actions,
  workflow_dispatch, terraform plan/apply in CI, or an AWS deploy role — you
  don't need the word "skill" said.
---

# cicd — authoring & refactoring GitHub Actions deploy pipelines

## What this skill is for

Deploy workflows accrete: static AWS keys in secrets, a single job that plans and
applies on every push (including PRs), Lambda packaging steps that predate a code
refactor, a frontend synced with hardcoded config, and no separation between
"show me what will change" and "actually change it." They work until they apply
something unreviewed to prod.

This skill gives you a **safe, OIDC-based Terraform+AWS pipeline shape**: federated
short-lived credentials, plan on PRs / apply on the default branch behind a gate,
Lambda packaged from source, and a frontend deploy that injects real
infrastructure values before syncing and invalidates the CDN. The focus is
GitHub Actions deploying an AWS serverless stack via Terraform.

## The core idea: separate *what will change* from *changing it*

The single most important property of a deploy pipeline is that **applying is
gated and deliberate**, while **planning is cheap and automatic**. Structure the
workflow around that split:

```
on PR            -> fmt, validate, plan  (read-only; show the diff, never apply)
on push to main  -> plan, then apply     (apply behind an environment gate)
manual dispatch  -> plan / apply / destroy chosen explicitly
```

Everything else (credentials, packaging, frontend sync) serves this: a human (or a
required reviewer) sees the plan before anything mutates infrastructure.

## Workflow

When authoring or refactoring a pipeline, work in this order. Each step has a
reference file — read it when you reach that step.

1. **Credentials first: OIDC, not static keys.** Replace
   `AWS_ACCESS_KEY_ID`/`SECRET` secrets with a federated role assumed via GitHub's
   OIDC provider. This is the highest-value change — it removes long-lived
   secrets. See `references/oidc-auth.md`.

2. **Trigger + gating model.** PRs plan; the default branch applies; destroys are
   explicit. Add an environment protection gate on apply. See
   `references/gating.md`.

3. **Terraform steps.** init (partial backend from secrets/vars), fmt-check,
   validate, plan (save the plan), apply the *saved* plan. See
   `references/terraform-steps.md`.

4. **Artifact build: package the Lambda from source.** Zip the function's source
   package (and only real dependencies) — matching how the Terraform expects it.
   See `references/artifacts.md`.

5. **Frontend deploy: inject config, sync, invalidate.** Substitute Terraform
   outputs into the frontend config, sync to S3, invalidate CloudFront. See
   `references/frontend-deploy.md`.

You won't always do all five — for a targeted fix, jump to the step that's broken.
But do check step 1 first on any pipeline still using static keys: it's the change
that matters most and it changes how every later AWS step authenticates.

## Least-privilege for the workflow itself

A workflow using OIDC needs explicit `permissions`. Grant the minimum:

```yaml
permissions:
  id-token: write   # REQUIRED to request the OIDC token for AWS
  contents: read    # to check out the repo
  # pull-requests: write   # only if the workflow comments the plan on PRs
```

Without `id-token: write`, OIDC auth silently can't get a token. Don't grant
`write` scopes the jobs don't use — the default token is powerful.

## Reference files

Read these as you hit the matching step:

- `references/oidc-auth.md` — `aws-actions/configure-aws-credentials` with
  `role-to-assume`, the `id-token: write` permission, and how the role's trust
  policy pairs with the workflow (repo/branch scoping).
- `references/gating.md` — trigger design (PR vs. push vs. dispatch), path
  filters, environment protection rules for apply approval, and the
  `if:` conditions that keep apply off PRs.
- `references/terraform-steps.md` — init with partial backend config, fmt/validate,
  `plan -out`, applying the *saved* plan (not a re-plan), and `-var-file`.
- `references/artifacts.md` — packaging a Python Lambda from `src/` to match the
  Terraform `archive_file`, when a dependencies layer is/ isn't needed, and
  keeping packaging deterministic.
- `references/frontend-deploy.md` — reading `terraform output` into env,
  substituting a frontend `config.js`, `aws s3 sync` (with `--delete`), and
  `cloudfront create-invalidation`.

## Assets

- `assets/deploy.yml` — a complete reference workflow implementing the shape
  above: OIDC auth, PR-plan / main-apply / dispatch-destroy, saved-plan apply,
  Lambda packaging from source, and frontend config-inject + sync + invalidate.
  Copy and adapt the names/paths.

## Anti-patterns to fix on sight

The recurring problems in hand-grown deploy workflows. When refactoring, hunt for
these:

- **Static AWS keys in secrets** (`AWS_ACCESS_KEY_ID`/`SECRET`) — replace with
  OIDC. Long-lived keys in CI are the biggest risk here.
- **Apply runs on pull requests** — PRs must be read-only (plan). Applying
  unreviewed PR code to infrastructure is the worst-case failure.
- **Plan then a *separate* apply that re-plans** — apply a saved plan file so what
  was reviewed is exactly what runs. A re-plan can diverge.
- **No approval gate on apply** — use a GitHub Environment with required
  reviewers so a human confirms before prod changes.
- **`continue-on-error` on plan masking failures** — a failed plan should stop the
  pipeline, not silently proceed to apply.
- **Packaging steps that predate a code refactor** — e.g. zipping a single
  `main.py` or building a dependency layer no longer needed. Match packaging to
  the current source layout and the Terraform's expectations.
- **Frontend synced with placeholder/hardcoded config** — inject real Terraform
  outputs before sync, and invalidate CloudFront after, or users get stale files.
- **Missing `permissions:` block** — OIDC needs `id-token: write`; without it auth
  fails confusingly.
