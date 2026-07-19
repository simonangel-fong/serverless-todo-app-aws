# Variables & outputs

Variables are a module's input contract; outputs are its output contract. Treat
them as an API: typed, described, and minimal.

## Variables

Every variable gets a **type** and a **description**. The type catches wrong-shape
inputs at plan time; the description is what a consumer reads to use the module.

```hcl
variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names, e.g. \"todo-app-dev\"."
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource in this module."
  default     = {}
}
```

**Validate constrained values** so a bad input fails fast with a clear message
instead of erroring deep in a provider call:

```hcl
variable "environment" {
  type        = string
  description = "Deployment environment."
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "lambda_runtime" {
  type        = string
  description = "Lambda runtime identifier."
  default     = "python3.12"
}
```

**Mark secrets `sensitive`** so they don't print in plan/apply output:

```hcl
variable "api_token" {
  type      = string
  sensitive = true
}
```

### Defaults: required vs. optional

- **No default → required input.** Use this for things that *must* be supplied and
  have no safe universal value (account-specific names, the ACM cert ARN).
- **Default → optional with a sane fallback.** Use for genuinely reusable defaults
  (runtime, region for a single-region app).

Watch for the anti-pattern: a variable whose default is the *only* value ever used
and which nothing overrides. That's not configuration, it's a constant with extra
indirection — inline it as a `local` or literal unless you expect it to vary.

## Outputs

Outputs exist for **consumers** — another module, the root, or a human running
`terraform output`. Export what a consumer needs to wire to this module, not every
attribute of every resource.

```hcl
output "table_name" {
  description = "DynamoDB table name, for the Lambda env and IAM policy."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "DynamoDB table ARN, for the IAM policy resource scope."
  value       = aws_dynamodb_table.this.arn
}

output "owner_index_name" {
  description = "Name of the owner-index GSI, for the Lambda's query."
  value       = "owner-index"
}
```

Guidelines:

- **Describe accurately.** Copy-pasted descriptions ("S3 bucket name" on a DynamoDB
  output) are a real bug magnet — the description is documentation.
- **Don't dump everything.** If nothing consumes an attribute, it doesn't need an
  output. Outputs are surface area.
- **Mark sensitive outputs `sensitive`** so they don't leak into logs.
- **Root outputs** are the stack's public interface — the URL, the API endpoint,
  the bucket name a deploy step needs. Keep them purposeful too.

## Reducing variable sprawl

A flat config often accumulates many single-use variables. When refactoring:

- Fold values that always move together into one `object` variable or a `local`.
- Delete variables no resource references anymore.
- Move truly-constant "variables" into `locals`.
- Group related variables with comments, and keep each module's variables in that
  module — don't pass everything down from a giant root variable list the module
  doesn't use.
