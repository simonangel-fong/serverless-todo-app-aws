# Serverless Todo List

A cloud-native, multi-user todo app on AWS — serverless API, static frontend,
fully managed with Terraform and deployed via GitHub Actions (OIDC).

## Stack

| Layer     | Tech                                                              |
| --------- | ---------------------------------------------------------------- |
| Frontend  | Static HTML/JS on **S3** (private) + **CloudFront** (OAC, HTTPS)  |
| API       | **API Gateway** (REST) → **Lambda** (Python)                     |
| Auth      | **Cognito** user pool; ID token on every request (404 ownership) |
| Data      | **DynamoDB** (`id` PK + `owner-index` GSI)                       |
| DNS       | **Cloudflare** CNAME → CloudFront                                |
| IaC       | **Terraform** (remote S3 state)                                  |
| CI/CD     | **GitHub Actions** — OIDC, Trivy scan, plan/apply gating         |
| Monitoring| **CloudWatch** alarms + dashboard                               |

![architecture](./architecture.png)

## Layout

```
infra/    Terraform (one file per resource group) + dev.tfvars
lambda/   src/ (handler→service→repository) + tests/
web/      static frontend (config.js rendered by Terraform)
docs/     API contract + project plan
.github/  deploy.yml, destroy.yml, dependabot.yml
```

## Deploy

Deployment runs through GitHub Actions. Required repo secrets:
`AWS_DEPLOY_ROLE_ARN`, `AWS_REGION`, `TF_STATE_BUCKET`, `TF_STATE_KEY`,
`CLOUDFLARE_API_TOKEN` — plus a `production` environment with reviewers.

- **PR** → format / validate / plan (read-only)
- **Push to `master`** → plan, then gated apply
- **`destroy.yml`** → manual teardown (typed confirmation + approval)

Terraform packages the Lambda (`lambda/src/`) and uploads `web/` itself, so no
separate build step.

### Run locally

```sh
cd infra
cp backend.hcl.example backend.hcl   # fill in state bucket
terraform init -backend-config=backend.hcl
terraform apply -var-file=dev.tfvars
```

Lambda tests: `cd lambda && python -m pytest tests/`

## Details

See [`docs/api-contract.md`](docs/api-contract.md) for the API + auth model and
[`docs/project.md`](docs/project.md) for the design/refactor history.
