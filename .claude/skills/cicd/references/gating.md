# Triggers & gating

The pipeline's job is to make **planning automatic and applying deliberate**. That
comes down to trigger design plus `if:` conditions plus an environment gate.

## Trigger model

```yaml
on:
  pull_request:
    branches: [main]
    paths: [infra/**, lambda/**, web/**, .github/workflows/**]
  push:
    branches: [main]
    paths: [infra/**, lambda/**, web/**, .github/workflows/**]
  workflow_dispatch:
    inputs:
      action:
        description: Terraform action
        type: choice
        options: [plan, apply, destroy]
        default: plan
```

- **pull_request** → plan only. Reviewers see the diff on the PR; nothing mutates.
- **push to main** (merge) → plan then apply.
- **workflow_dispatch** → a human picks `plan` / `apply` / `destroy` explicitly.
  This replaces brittle patterns like reading an action out of a committed file.

**Path filters** keep the pipeline from running on unrelated commits (docs, README).
List the dirs that actually affect the deploy.

## Keeping apply off PRs

Trigger design alone isn't enough — guard the apply step with an explicit
condition so it can only run on a push to main or a dispatch that asked for it:

```yaml
- name: Terraform Apply
  if: >-
    (github.event_name == 'push' && github.ref == 'refs/heads/main') ||
    (github.event_name == 'workflow_dispatch' && inputs.action == 'apply')
  run: terraform -chdir=infra apply -auto-approve tfplan
```

The plan step, by contrast, runs on every trigger — it's safe and it's the whole
point of a PR run.

## Approval gate: GitHub Environments

For a human confirmation before infrastructure changes, put the apply job in a
**GitHub Environment** with a required reviewer:

```yaml
jobs:
  apply:
    environment: production   # configure required reviewers on this env in repo settings
    ...
```

When a job targets a protected environment, GitHub pauses it until an authorized
reviewer approves. This is the difference between "merge silently applies" and "a
human clicks approve." Configure the reviewers in **Settings → Environments** —
the workflow only names the environment; the protection rules live in repo config.

For a stronger setup, split into two jobs: a `plan` job (runs everywhere) and an
`apply` job that `needs: plan`, targets the protected environment, and consumes
the plan artifact. The gate then sits exactly at the mutation boundary.

## Destroy is explicit, always

Never wire `destroy` to a push or PR. It belongs only behind `workflow_dispatch`
with the action explicitly chosen (and ideally the same environment gate). An
accidental destroy is unrecoverable in a way an accidental apply usually isn't.
