# Structure: root module vs. child modules

The goal is a root that reads like an architecture diagram and modules that are
each responsible for one resource group with a clear contract.

## Root vs. child

**Root module** (the top directory) owns everything global and does the wiring:

- `terraform {}` block: `required_version`, `required_providers`, `backend`.
- `provider` blocks (with `default_tags`).
- shared `locals` (naming prefix, tags).
- root `variables.tf` (the inputs a human/CI supplies) and `outputs.tf` (what the
  whole stack exposes).
- **module calls**, passing one module's outputs as another's inputs.

**Child module** (`modules/<name>/`) owns one resource group and *nothing global*:

- **No** `provider` block, **no** `backend`, **no** `required_providers` source
  config beyond a `versions.tf` constraint if needed. Providers are inherited from
  the root.
- Everything it needs comes in through `variables.tf`.
- Everything another module needs comes out through `outputs.tf`.
- No hardcoded names — names are built from an input like `var.name_prefix`.

## The standard three-file module

Every module is the same shape, which makes them predictable to read:

```
modules/dynamodb/
├── main.tf        # the resources
├── variables.tf   # typed, described inputs
└── outputs.tf     # what consumers need (table name, arn, index name, ...)
```

Root wiring looks like:

```hcl
# root main.tf
module "dynamodb" {
  source      = "./modules/dynamodb"
  name_prefix = local.name_prefix
  tags        = local.tags
}

module "lambda" {
  source      = "./modules/lambda"
  name_prefix = local.name_prefix
  tags        = local.tags
  table_name  = module.dynamodb.table_name    # output -> input wiring
  table_arn   = module.dynamodb.table_arn      # (e.g. for the IAM policy)
}
```

The dependency order is expressed by these output→input references — Terraform
builds the graph from them, so you rarely need explicit `depends_on` between
modules.

## Migration path from flat `tf_*.tf`

Refactoring a flat directory (all `tf_dynamodb.tf`, `tf_lambda.tf`, ... at the
root) into modules, one group at a time:

1. **Create `modules/<group>/`** with the three files.
2. **Move the resources** from `tf_<group>.tf` into the module's `main.tf`.
3. **Parameterize**: replace hardcoded names with `var.name_prefix`-derived names;
   replace direct cross-file references (`aws_dynamodb_table.x.arn`) with a module
   input passed from the root.
4. **Add outputs** for anything another file referenced.
5. **Add a `module` call** in the root and rewire references to
   `module.<group>.<output>`.
6. **Add `moved` blocks** so state follows the resources to their new addresses —
   see `verification.md`. This step is not optional for stateful resources.
7. **`plan`** and confirm no destroy/create of stateful resources.

Do this **one group at a time**, planning after each, so a surprise in the plan is
attributable to the group you just moved.

## When NOT to modularize

Modules earn their keep when a resource group is non-trivial, reused, or varies by
environment. They cost indirection. Skip a module when:

- It would wrap a single resource with no logic (just inline the resource).
- The "module" has one caller and never will have more — a `locals` block or a
  `for_each` often expresses the intent more directly.
- Splitting would scatter tightly-coupled resources that always change together.

The right grain here is **one module per resource group** (dynamodb, lambda,
apigateway, s3, cloudfront, iam, cloudwatch), because those are the units that get
refactored and reasoned about independently.
