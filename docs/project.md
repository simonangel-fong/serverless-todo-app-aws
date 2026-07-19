# Serverless Todo List — Project Plan

## Goal

Refactor the project end to end:

- Restructure the file/folder layout.
- Build a reusable **skill** for authoring & refining Python Lambda functions.
- Build a reusable **skill** for authoring & refining the GitHub Actions pipeline that deploys Terraform + AWS.
- Refactor the Terraform, Lambda, and CI/CD code against those skills.

---

## Stack

| Area          | Choice                     |
| ------------- | -------------------------- |
| API compute   | Lambda function            |
| API runtime   | Python                     |
| Database      | DynamoDB                   |
| API           | API Gateway (REST)         |
| Frontend      | S3 bucket + CloudFront     |
| Auth          | Cognito (added in Phase 4) |
| IaC           | Terraform (`aws` provider) |
| State backend | Remote state bucket        |
| OIDC role     | IAM (GitHub OIDC)          |
| CI/CD         | GitHub Actions with OIDC   |
| Monitoring    | CloudWatch                 |

> **Note:** the current codebase uses **DynamoDB** (an earlier draft of this doc said Cosmos)
> and has **no auth yet**. Cognito is added as part of this refactor (Phase 4), not deferred —
> so each component is touched once.

---

## Current file structure

```txt
.github/workflows/   # CI/CD (deploy.yml)
lambda/              # Python Lambda handler + requirements.txt
s3/                  # static frontend (index.html, create.html, data/)
terraform/           # all *.tf (one file per resource group)
docs/                # this plan
README.md
architecture.png
```

### Target file structure

```txt
.claude/skills/      # lambda-py, terraform-wf, cicd skills
.github/workflows/   # CI/CD
infra/               # Terraform (renamed from terraform/)
  modules/           # dynamodb, lambda, apigateway, s3, cloudfront, iam
lambda/
  src/               # handler + business logic
  tests/             # unit tests
web/                 # static frontend (renamed from s3/)
docs/
README.md
```

---

## Data model — DynamoDB table `todo-app-table`

Partition key: **`id`** (string, UUID). Single-table, no sort key.
**GSI `owner-index`**: partition key `owner_id` — supports "list all todos for this user"
as a `query` instead of a `scan`.

```json
{
  "id": "<uuid>",              // table partition key
  "owner_id": "<cognito-sub>", // GSI partition key; from the caller's token, never the body
  "task_name": "string",       // required
  "task_priority": "High | Medium | Low",   // default "Medium"
  "task_status": "Pending | In Progress | Completed",  // default "Pending"
  "due_date": "ISO-8601 | null",
  "created_at": "ISO-8601"     // set on create
}
```

> **Why `owner_id` is designed in now (not deferred):** adding auth later would force us to
> re-open DynamoDB (add the GSI), the Lambda (scope every route), and API Gateway (authorizer)
> a second time — after Phase 4 already touched them. Building `owner_id` in from the start
> means each component is refactored **once**. Keeping PK=`id` + a GSI avoids any data
> migration.

---

## API contract

Base path served by API Gateway, protected by a **Cognito authorizer**. Every request
carries a verified identity; the caller's `sub` is read from
`event.requestContext.authorizer.claims.sub` and used as `owner_id`.
Routes are `/items` and `/items/{id}`.
Responses are wrapped: `{ "message": string, "data"?: ..., "error"?: string }`.

| Method | Route          | Behavior                                          | Success     | Errors            |
| ------ | -------------- | ------------------------------------------------- | ----------- | ----------------- |
| GET    | `/items`       | list caller's items (`query` on `owner-index`)    | 200 + array | 401               |
| POST   | `/items`       | create (body requires `task_name`)                | 201 + item  | 400 / 401         |
| GET    | `/items/{id}`  | fetch one (must belong to caller)                 | 200 + item  | 401 / 404         |
| PUT    | `/items/{id}`  | update mutable fields (must belong to caller)     | 200 + item  | 400 / 401 / 404   |
| DELETE | `/items/{id}`  | delete (must belong to caller)                    | 200         | 401 / 404         |

**Ownership rule:** for `/items/{id}`, if the item's `owner_id` ≠ caller, return **404**
(not 403 — don't leak that the id exists). `owner_id` is always taken from the token, never
from the request body.

### Known contract issues to fix during refactor

- **DELETE returns 200, not 204** — decide and make consistent.
- **PUT does not 404** on a missing id (blind `update_item` upserts). Add an existence check.
- **PUT success response omits `data`** — return the updated item for consistency with POST/GET.
- **No CORS preflight (OPTIONS)** handling in the Lambda — currently only `Access-Control-Allow-Origin: *` on responses.
- **`GET /items` must not `scan`** — use the `owner-index` GSI so it returns only the caller's items.

---

## Phases

**Phase 0 — API redesign (auth included)** ✅ *done — see [`api-contract.md`](api-contract.md)*
Lock the contract above; resolve the "known contract issues"; document request/response
shapes. Define the auth model: Cognito authorizer, `owner_id` from the token, the 404
ownership rule.

**Phase 1 — `lambda-py` skill** ✅ *done — see [`.claude/skills/lambda-py/`](../.claude/skills/lambda-py/SKILL.md)*
Create a skill for authoring/refining Python Lambda functions (structure, validation,
error handling, test scaffolding). Built before the Lambda refactor so the refactor is
driven by the skill.

**Phase 2 — Lambda refactor (auth-aware, using `lambda-py`)** ✅ *done — code in [`lambda/src/`](../lambda/src/handler.py), tests in [`lambda/tests/`](../lambda/tests/)*
Refactor `lambda/main.py`: split routing from business logic, add input validation,
consistent error handling, and structured logging. **Scope every route by `owner_id`**
(read `sub` from the authorizer claims; `GET /items` queries `owner-index`; stamp `owner_id`
on create; enforce the ownership rule on get/put/delete). Add unit tests (`lambda/tests/`),
including ownership/isolation cases.

> Layered as handler → service → repository (+ errors/validation/responses/logging_setup).
> 24 unit tests pass, incl. cross-owner isolation on get/put/delete. Old `lambda/main.py`
> is left in place but marked **deprecated** so Terraform still plans; **Phase 4** rewires
> packaging to `lambda/src/` (entry point `handler.lambda_handler`) and removes `main.py`,
> and **Phase 6** updates CI packaging.

**Phase 3 — `terraform-wf` skill** ✅ *done — see [`.claude/skills/terraform-wf/`](../.claude/skills/terraform-wf/SKILL.md)*
Create a skill for authoring/refining Terraform (module layout, naming, variables, outputs).

**Phase 4 — Terraform refactor by resource (using `terraform-wf`)**
Refactor each resource group in order. Rename `terraform/` → `infra/`, introduce modules.

1. DynamoDB — table **plus `owner-index` GSI** ✅ *done — [`infra/modules/dynamodb/`](../infra/modules/dynamodb/main.tf)*
2. Lambda ✅ *done — [`infra/lambda.tf`](../infra/lambda.tf); handler `handler.lambda_handler`, `src/` packaged, env vars wired, dependency layer dropped, exec role least-privilege*
3. **Cognito** — user pool + app client ✅ *done — [`infra/cognito.tf`](../infra/cognito.tf); email sign-in pool + public SPA client (no secret, SRP + code flow)*
4. API Gateway — **wire the Cognito authorizer** onto the routes ✅ *done — [`infra/apigateway.tf`](../infra/apigateway.tf); routes via `for_each` (~580 lines → ~1 file), Cognito authorizer on every route, OPTIONS MOCK preflight, Lambda invoke permission*
5. S3 bucket ✅ *done — [`infra/s3.tf`](../infra/s3.tf); private bucket (all public access blocked), OAC-only read (policy in CloudFront step), provision-only (CI/CD uploads)*
6. CloudFront
7. IAM / GitHub OIDC role
8. CloudWatch

**Phase 5 — Frontend refactor**
Refactor `s3/` HTML (rename → `web/`); align with the finalized API contract.
Add the Cognito sign-in flow and send the token on every API call.

**Phase 6 — `cicd` skill + pipeline refactor**
Create the CI/CD skill, then refactor `.github/workflows/deploy.yml` (OIDC, plan/apply gating,
Lambda packaging, frontend sync + CloudFront invalidation).

---

## Roadmap (post-refactor)

- Add integration/e2e tests in CI (authenticated request flows).
- Consider repartitioning to PK=`owner_id`, SK=`id` if single-user query volume outgrows the GSI.
