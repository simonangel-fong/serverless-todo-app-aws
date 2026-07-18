---
name: terraform-wf
description: >-
  Author and refactor Terraform (AWS-focused): module layout, resource naming,
  variables, outputs, tagging, and provider/backend setup. Use this whenever you
  are writing new Terraform, restructuring a flat pile of *.tf files into
  modules, introducing consistent naming or tags, cleaning up variables/outputs,
  wiring a remote state backend, or reviewing an existing configuration for
  drift, duplication, and hardcoded values. Trigger even when the user just says
  "clean up the terraform", "these tf files are a mess", "turn this into
  modules", "the naming is inconsistent", "add tags everywhere", or mentions HCL,
  a resource group (DynamoDB/Lambda/API Gateway/S3/CloudFront/IAM/CloudWatch),
  .tf files, tfvars, or state backends — you don't need the word "skill" said.
---

# terraform-wf — authoring & refactoring Terraform

## What this skill is for

Terraform tends to grow as one flat directory of `tf_<resource>.tf` files, each
hand-written, with names built by string concatenation, tags applied unevenly,
values hardcoded in one place and variabilized in another, and large blocks of
near-identical resources copy-pasted (API Gateway methods are the classic case).
It *works*, but it's hard to change safely and impossible to reuse.

This skill gives you a **module-oriented layout**, consistent **naming/tagging**
conventions, and disciplined **variables/outputs** — so each resource group is
defined once, wired through clear inputs, and reusable across environments. The
focus is the AWS provider, but the structure and conventions are provider-neutral.

## The core idea: root composes, modules implement

Keep a thin **root module** that wires things together, and put each resource
group in its own **child module** with a clear input/output contract. The root
knows *what* to build and how pieces connect; a module knows *how* to build its
one thing.

```
root  (compose)   provider + backend, shared locals (naming/tags), module calls,
   │              passing outputs of one module as inputs to the next
   └── modules/
       dynamodb/  each module: main.tf + variables.tf + outputs.tf
       lambda/    no provider/backend block, no hardcoded names — everything it
       apigateway/ needs comes in through variables; everything others need comes
       s3/        out through outputs
       ...
```

The payoff: the root reads like an architecture diagram, a module is testable and
reusable in isolation, and a change to one resource group touches one directory.
Layout details and the migration path from flat files are in
`references/structure.md`.

Don't over-modularize. A module per *resource group* (dynamodb, lambda,
apigateway, ...) is the right grain. A module wrapping a single `aws_s3_bucket`
with no logic adds indirection without payoff — inline it. Match module boundaries
to things that genuinely vary together or get reused.

## Workflow

When authoring or refactoring, work in this order. Each step has a reference file
— read it when you reach that step rather than loading everything up front.

1. **Set the foundation: provider, backend, naming, tags.** Pin provider
   versions, configure remote state, and establish one naming convention and one
   set of default tags as shared `locals`. Everything downstream depends on these,
   so lock them first. See `references/foundation.md`.

2. **Carve modules by resource group.** One directory per group, each with
   `main.tf` / `variables.tf` / `outputs.tf`. Move resources in, replace hardcoded
   names/ids with variables, expose what other modules need as outputs. See
   `references/structure.md`.

3. **Clean variables and outputs.** Every variable typed and described; validate
   the ones with constrained values; remove dead/duplicated ones; make outputs
   purposeful (what a *consumer* needs), not a dump of every attribute. See
   `references/variables-outputs.md`.

4. **Collapse repetition.** Copy-pasted resource blocks (API Gateway
   method/integration sets, per-route IAM statements) become `for_each` over a map
   or a small reused module. See `references/patterns.md`.

5. **Verify.** `fmt`, `validate`, and a `plan` that shows no unexpected changes —
   especially that a refactor didn't accidentally force-replace stateful resources.
   See `references/verification.md`.

You won't always do all five — for a targeted cleanup, jump to the steps that
address the real problem. But always finish with step 5: the whole risk in
refactoring Terraform is silently changing what gets created or destroyed.

## Refactoring safely: the address-move rule

The single biggest hazard when restructuring Terraform is that **moving a resource
into a module changes its state address** (`aws_s3_bucket.x` →
`module.s3.aws_s3_bucket.x`). Terraform then plans to *destroy the old and create
a new* — catastrophic for a database, a bucket with data, or anything with a
stable name.

Prevent it with `moved` blocks (or `terraform state mv`) so Terraform treats it as
the same resource at a new address. Any refactor that relocates resources must
account for this before `apply`. Details and examples in
`references/verification.md` — read it before moving stateful resources.

## Reference files

Read these as you hit the matching step:

- `references/foundation.md` — provider version pinning, S3/remote backend,
  naming convention via `locals`, `default_tags`, and per-environment config.
- `references/structure.md` — root vs. child modules, the standard three-file
  module, the migration path from flat `tf_*.tf` files, when *not* to modularize.
- `references/variables-outputs.md` — typing, descriptions, `validation` blocks,
  sensitive vars, sane defaults vs. required inputs, purposeful outputs.
- `references/patterns.md` — `for_each` vs. `count`, collapsing duplicated blocks,
  data sources vs. hardcoded ids, `depends_on` hygiene.
- `references/verification.md` — `fmt`/`validate`/`plan`, reading a plan for
  unintended replacements, and `moved` blocks / `state mv` for safe relocation.

## Assets

- `assets/module_template/` — a ready-to-copy `main.tf` / `variables.tf` /
  `outputs.tf` skeleton for a new resource-group module, with the naming/tags
  wiring already in place. Copy it into `modules/<name>/` and fill in.

## Anti-patterns to fix on sight

The recurring smells in hand-grown Terraform. When refactoring, hunt for these:

- **Names built by ad-hoc string concat** scattered across files — centralize a
  naming convention in `locals` (e.g. `local.name_prefix`) and derive from it.
- **Tags applied unevenly** — some resources tagged, some not, keys inconsistent.
  Use provider `default_tags` plus a shared `local.tags`, so every resource is
  tagged the same way without repetition.
- **Hardcoded values that should be variables** (regions, runtimes,
  architectures, account ids) — and the reverse, variables with a single
  hardcoded default nobody ever overrides.
- **Copy-pasted resource blocks** differing only in one string — collapse with
  `for_each`.
- **Empty or committed backend config** — the backend block with blank
  `bucket`/`key`, or real values hardcoded. Use partial config + a backend file.
- **Outputs that dump every attribute** or duplicate each other's descriptions —
  export only what a consumer needs, described accurately.
- **Provider/backend blocks inside would-be modules** — modules must not declare
  providers or backends; those belong to the root.
- **Refactors that don't use `moved` blocks** — relocating a resource silently
  becomes destroy+create. See the address-move rule above.
