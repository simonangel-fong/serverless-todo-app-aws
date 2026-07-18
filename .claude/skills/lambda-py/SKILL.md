---
name: lambda-py
description: >-
  Author and refactor Python AWS Lambda handlers, with a focus on API Gateway
  (proxy integration) functions backed by DynamoDB. Use this whenever you are
  writing a new Lambda, refactoring an existing handler (e.g. splitting a big
  lambda_handler into routing + business logic), adding request validation,
  fixing inconsistent HTTP responses, scoping routes by an authenticated
  caller's identity, adding structured logging, or scaffolding unit tests for a
  Lambda. Trigger even when the user just says "clean up this Lambda", "the
  handler is a mess", "add validation", "make the responses consistent", or
  mentions API Gateway events, DynamoDB access from a Lambda, or Cognito
  authorizer claims — you don't need the word "skill" to be said.
---

# lambda-py — authoring & refactoring Python Lambda handlers

## What this skill is for

Python Lambdas start as one `lambda_handler` that grows into a tangle: routing,
JSON parsing, validation, database calls, and response formatting all interleaved
in one 150-line function with duplicated `try/except` and inconsistent status
codes. This skill gives you a **layered structure** and a set of patterns that
keep the handler thin and the logic testable, so the same shape works for the
next Lambda too.

The center of gravity is **API Gateway (proxy integration) → Lambda → DynamoDB**,
because that's the most common web-API shape, but the layering and the
validation/error/logging patterns apply to any trigger.

## The core idea: three layers

Keep these responsibilities in separate places. The whole point is that the
middle layer — where the actual work lives — never touches raw AWS event shapes,
so you can unit-test it by calling plain functions with plain dicts.

```
handler  (thin)   parse event → extract identity → dispatch → format response
   │
service  (logic)  validate input, enforce rules, call the data layer, return
   │               plain Python results or raise typed errors
   │
data     (I/O)    DynamoDB / other AWS calls; the only layer that knows boto3
```

For a small Lambda this can be three functions in one file with clear sections;
for a larger one, three modules (`handler.py`, `service.py`, `repository.py`).
Don't over-split a 40-line Lambda into a package — match the ceremony to the size.
Structure guidance lives in `references/structure.md`.

## Workflow

When authoring or refactoring a Lambda, work in this order. Each step has a
dedicated reference file — read it when you reach that step rather than loading
everything up front.

1. **Understand the contract first.** What routes/events, what inputs, what
   responses (status codes + body shape), what identity model? If the project
   has an API contract doc, that is the source of truth — implement it, don't
   reinvent it. If there isn't one, pin down the response envelope before writing
   code, because consistency is the thing that's hardest to retrofit.

2. **Shape the handler (routing).** Thin dispatch on method + path. Extract the
   caller identity once, at the top. See `references/structure.md`.

3. **Validate input at the boundary.** Reject bad input with `400` before any
   business logic runs. See `references/validation.md`.

4. **Make responses and errors consistent.** One response-builder, one error
   taxonomy, one place that turns errors into status codes. This is where most
   "known issues" in an existing handler get fixed. See `references/responses.md`.

5. **Add structured logging.** JSON logs with a request id and the route, no
   secrets or full tokens. See `references/logging.md`.

6. **Scaffold tests.** Unit-test the service layer directly; test the handler
   with synthetic events. Include auth/isolation cases if the Lambda is scoped by
   caller. Start from `assets/test_handler_template.py` and
   `references/testing.md`.

You won't always do all six — for a refactor, jump to the steps that address the
actual problems. But do check every layer, because the usual failure mode is
fixing routing while leaving responses inconsistent.

## Identity & authorization (API Gateway + authorizer)

When a Lambda sits behind an authorizer (Cognito, a custom authorizer, etc.), the
caller's identity arrives in the event, **not** the request body. Read it once in
the handler and pass it down:

```python
claims = event["requestContext"]["authorizer"]["claims"]
caller_id = claims["sub"]          # stable per-user id
```

Two rules that prevent whole classes of bugs:

- **Never trust the body for identity or ownership.** If the client sends an
  `owner_id`/`user_id`, ignore it — use the value from the claims. Otherwise any
  caller can act as anyone.
- **Scope every data access by the caller.** List = query on the owner index (not
  a full `scan`). Get/update/delete = fetch, then check ownership. When an item
  exists but isn't the caller's, prefer returning **404** over 403 so you don't
  leak which ids exist. (Follow the project's contract if it specifies otherwise.)

See `references/structure.md` for how this threads through the layers.

## Reference files

Read these as you hit the matching step — they hold the patterns and code shapes:

- `references/structure.md` — the three layers, handler dispatch, threading
  identity through, when to use one file vs. a package.
- `references/validation.md` — validating required fields, enums, types; where
  validation belongs; returning `400` cleanly.
- `references/responses.md` — the response envelope, a `response()` helper, a
  typed error taxonomy, and the error→status mapping. Read this to fix
  inconsistent status codes and missing bodies.
- `references/logging.md` — structured JSON logging, what to include, what never
  to log.
- `references/testing.md` — how to test each layer, synthetic API Gateway events,
  auth/isolation cases, and how to fake DynamoDB.

## Assets

- `assets/test_handler_template.py` — a starting-point pytest file: a
  `make_event()` helper for synthetic API Gateway proxy events, a fake table, and
  example tests including an ownership-isolation case. Copy it into the project's
  `tests/` and adapt.

## Anti-patterns to fix on sight

These are the recurring problems in hand-grown Lambda handlers. When refactoring,
hunt for them specifically:

- **`scan` to list one user's items** — replace with a `query` on an index.
- **Blind `update_item` that upserts** — a `PUT` to a missing id silently creates
  a row. Check existence (and ownership) first.
- **Update/delete responses that omit the resulting item** while create/get
  return it — make the shape consistent.
- **Inconsistent status codes** — the same class of failure returning 400 in one
  route and 500 in another. Route everything through the error taxonomy.
- **One giant `try/except Exception`** that turns every bug into a 500 with a raw
  string — catch typed errors for expected cases, keep a last-resort 500 for the
  truly unexpected, and log it.
- **Identity read from the body** — see the identity section above.
