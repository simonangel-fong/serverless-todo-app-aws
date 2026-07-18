# Foundation: provider, backend, naming, tags

Everything else in the configuration depends on these four things, so lock them
before touching resources. They're what make a config reproducible, portable
across environments, and consistently named.

## Provider version pinning

Pin the Terraform core and provider versions so a `terraform init` months later
doesn't silently pull a breaking major. Use `~>` to allow patches but not majors.

```hcl
# providers.tf (root only — never in a child module)
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.tags   # see "Tagging" below — tags every resource automatically
  }
}
```

## Remote backend

State must live remotely (S3 + native state locking, or another backend) so it's
shared, versioned, and not sitting on one laptop. Don't hardcode bucket/key in the
committed file — use **partial configuration** and supply the rest at init time,
so the same code initializes different backends per environment.

```hcl
# In the terraform {} block:
backend "s3" {}   # partial — values come from a backend config file
```

```hcl
# backend-dev.hcl   (git-ignored or per-env, passed at init)
bucket       = "myapp-tfstate-dev"
key          = "todo-app/terraform.tfstate"
region       = "ca-central-1"
use_lockfile = true          # S3-native locking (Terraform 1.10+; no DynamoDB table needed)
```

```bash
terraform init -backend-config=backend-dev.hcl
```

An empty committed backend block with blank `bucket`/`key`/`region` is a smell:
either it never initialized remote state, or the real values were stripped. Move
to partial config so the intent is explicit.

## Naming convention

Pick one convention and derive every name from it, so names are predictable and a
single change (the prefix) renames consistently. Centralize it in `locals`:

```hcl
# locals.tf
locals {
  name_prefix = "${var.app_name}-${var.environment}"   # e.g. "todo-app-dev"

  tags = merge(var.extra_tags, {
    Application = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}
```

Then resources derive names instead of hand-concatenating in each file:

```hcl
name = "${local.name_prefix}-table"       # not "${var.app_name}-table" everywhere
```

The win over scattered `"${var.app_name}-..."` strings: the convention lives in
one place, environment is baked in, and you can't accidentally name two things
inconsistently.

## Tagging

Two layers, and use both:

1. **`default_tags` on the provider** (shown above) — automatically applied to
   every taggable resource. This alone eliminates most "some resources aren't
   tagged" drift.
2. **A shared `local.tags`** for the values, merged with any per-resource
   additions where a resource genuinely needs an extra tag:

   ```hcl
   tags = merge(local.tags, { Name = "${local.name_prefix}-table" })
   ```

Avoid hand-writing a different `tags = { Name = ... }` block per resource with no
shared base — that's how tag keys drift apart.

## Environment separation

Keep environment-specific values (region, sizes, domain names, backend location)
in `*.tfvars` / backend config files, not in code. The code is the same across
environments; only the inputs change. This is what makes `dev` and `prod` the same
Terraform with different `-var-file`/`-backend-config`.
