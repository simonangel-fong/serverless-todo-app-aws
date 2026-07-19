# Terraform steps in CI

The Terraform sequence in a pipeline is: init → fmt-check → validate → plan → (gated)
apply. The one non-obvious discipline: **apply the plan you saved**, so what a
reviewer approved is exactly what runs.

## Init with a partial backend

The backend config shouldn't be committed (see terraform-wf). Supply it at init
from secrets/vars:

```yaml
- name: Terraform Init
  run: |
    terraform -chdir=infra init \
      -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}" \
      -backend-config="key=${{ secrets.TF_STATE_KEY }}" \
      -backend-config="region=${{ secrets.AWS_REGION }}"
```

Use `-chdir=infra` (or set a `working-directory`) so the whole job targets the
config directory consistently.

## fmt and validate as gates

```yaml
- name: Format check
  run: terraform -chdir=infra fmt -check -recursive

- name: Validate
  run: terraform -chdir=infra validate
```

`fmt -check` fails the run on unformatted code (a cheap consistency gate). Neither
should have `continue-on-error` — if formatting or validation fails, stop.

## Plan: save it

Always write the plan to a file so apply can consume the exact same plan:

```yaml
- name: Terraform Plan
  run: |
    terraform -chdir=infra plan \
      -var-file=dev.tfvars \
      -out=tfplan
```

Pass non-secret inputs via `-var-file`; pass secrets via `TF_VAR_*` env (e.g. a
Cloudflare token — never put it in a committed tfvars). On a PR, the plan *is* the
deliverable; optionally render it into the job summary or a PR comment so reviewers
see the diff without opening logs.

## Apply the saved plan

```yaml
- name: Terraform Apply
  if: >-
    (github.event_name == 'push' && github.ref == 'refs/heads/main') ||
    (github.event_name == 'workflow_dispatch' && inputs.action == 'apply')
  run: terraform -chdir=infra apply -auto-approve tfplan
```

Applying `tfplan` (not re-running `apply` with a fresh plan) guarantees the applied
changes equal the reviewed changes. A re-plan at apply time can pick up drift or a
concurrent change and do something nobody approved.

If plan and apply are **separate jobs** (recommended with an environment gate),
persist the plan between them with `actions/upload-artifact` / `download-artifact`,
and re-run `init` in the apply job (each job is a fresh runner).

## Passing secret variables

Secrets that Terraform needs as variables go through `TF_VAR_`:

```yaml
env:
  TF_VAR_cloudflare_api_token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

Terraform reads `TF_VAR_<name>` into `var.<name>` automatically — no `-var` on the
command line (which would risk logging the value).
