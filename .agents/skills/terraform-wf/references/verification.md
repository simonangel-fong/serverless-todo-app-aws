# Verification & safe refactoring

Refactoring Terraform is uniquely risky because the code and the *live
infrastructure* are coupled through state. A "cleanup" that reads fine can plan to
destroy a database. Always verify, and always account for moved addresses.

## The check sequence

Run these in order after any change:

```bash
terraform fmt -recursive        # canonical formatting; also a cheap syntax check
terraform validate              # internal consistency: types, references, required args
terraform plan                  # the real check — what WILL change
```

`fmt` and `validate` are static and fast. `plan` is the one that matters: it
compares desired state to real state and shows exactly what apply would do.

## Reading a plan for danger

The line to fear in a refactor is:

```
# aws_dynamodb_table.x must be replaced
-/+ resource "aws_dynamodb_table" "x" {
```

`-/+` (or "must be replaced" / "forces replacement") means **destroy then
create**. For a stateful resource — a database, an S3 bucket with objects, a
resource with a fixed name — that's data loss or a name collision.

After a pure refactor (moving/renaming code, not changing intent), the correct
plan is **"No changes"** or only cosmetic diffs. If you see creates and destroys of
things that already exist, the refactor changed a resource's *address*, not its
config — fix it with a `moved` block, don't apply.

## The `moved` block (the essential refactoring tool)

When you relocate a resource — into a module, or renaming its label — its state
address changes and Terraform thinks the old one is gone and a new one is needed.
A `moved` block tells Terraform "these are the same resource":

```hcl
# after moving aws_dynamodb_table.dynamodb_table into modules/dynamodb as "this"
moved {
  from = aws_dynamodb_table.dynamodb_table
  to   = module.dynamodb.aws_dynamodb_table.this
}
```

With the `moved` block present, `plan` shows the resource simply moving addresses
with no destroy/create. Add one for every relocated resource in a modularization
pass. `moved` blocks are safe to leave in the code; they're declarative and can be
cleaned up later once all states have caught up.

Alternative for a one-off, or when you can't express it declaratively:

```bash
terraform state mv aws_dynamodb_table.dynamodb_table \
                   module.dynamodb.aws_dynamodb_table.this
```

Prefer `moved` blocks — they're versioned with the code and run for everyone,
whereas `state mv` is a manual command each operator must run.

## Refactor loop

For a module migration, per resource group:

1. Move + parameterize the code.
2. Add `moved` blocks for every relocated resource.
3. `fmt` → `validate` → `plan`.
4. Confirm the plan shows **moves, not destroy/create**, for stateful resources.
5. Only then `apply` (or hand to CI). Then move to the next group.

Never batch-move everything and plan once at the end — if the plan is scary you
won't know which group caused it.

## Import for pre-existing resources

If a resource exists in the cloud but not in state (created by hand, or the state
was lost), bring it under management with an `import` block rather than letting
Terraform create a duplicate:

```hcl
import {
  to = module.s3.aws_s3_bucket.this
  id = "my-existing-bucket-name"
}
```

Then `plan` shows an import with (ideally) no changes, confirming the code matches
reality before you own it.
