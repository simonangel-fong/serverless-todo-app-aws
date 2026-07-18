# Patterns: collapsing repetition, data sources, dependencies

## `for_each` over copy-paste

The most common Terraform bloat is near-identical resource blocks that differ in
one string. API Gateway is the poster child: a `method` + `integration` +
`method_response` + `integration_response` set repeated per HTTP verb, often across
hundreds of lines. Collapse with `for_each` over a map.

Instead of four blocks per verb hand-written five times, describe the routes as
data and iterate:

```hcl
locals {
  methods = {
    get_all = { http_method = "GET",    resource_id = aws_api_gateway_resource.items.id }
    create  = { http_method = "POST",   resource_id = aws_api_gateway_resource.items.id }
    get_one = { http_method = "GET",    resource_id = aws_api_gateway_resource.item.id }
    update  = { http_method = "PUT",    resource_id = aws_api_gateway_resource.item.id }
    delete  = { http_method = "DELETE", resource_id = aws_api_gateway_resource.item.id }
  }
}

resource "aws_api_gateway_method" "m" {
  for_each      = local.methods
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = each.value.resource_id
  http_method   = each.value.http_method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "i" {
  for_each                = local.methods
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.m[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}
# ...and so on for the response resources, each keyed by each.key
```

Five verbs now live in one data structure. Adding a route is one map entry, not
another 80 lines. The same technique collapses per-route IAM statements, repeated
S3 objects, multiple similar CloudWatch alarms, etc.

## `for_each` vs. `count`

- **`for_each`** when instances have stable identities (named routes, a set of
  buckets). Keys are meaningful, so removing one doesn't reindex the others.
- **`count`** only for truly interchangeable N copies, or an on/off toggle
  (`count = var.enabled ? 1 : 0`).

Prefer `for_each`. With `count`, deleting the middle element shifts every later
index and Terraform plans to replace them all — a classic footgun.

## Data sources over hardcoded ids

Don't paste account ids, AMI ids, hosted zone ids, or managed policy ARNs as
string literals. Look them up so the config is portable and self-updating:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# use data.aws_caller_identity.current.account_id instead of a literal
```

For a value that genuinely lives outside this config (an ACM cert created
elsewhere, a pre-existing hosted zone), a **data source** that looks it up beats a
hardcoded id and beats a variable someone has to remember to set.

## Dependency hygiene

Terraform infers dependencies from references — if resource B uses
`aws_x.a.arn`, B already depends on A. So:

- **Prefer implicit dependencies.** Reference the attribute you need and let the
  graph form itself.
- **Use `depends_on` sparingly** — only for ordering that isn't expressed by any
  reference (e.g. an IAM policy that must exist before a service assumes the role,
  with no direct attribute link). Overusing `depends_on` serializes things that
  could run in parallel and hides the real data flow.
- When you catch a `depends_on` that duplicates an existing reference, remove it.
