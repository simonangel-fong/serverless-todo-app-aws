# Testing a Lambda

The layered structure exists so that most tests are plain function calls. Split
your effort:

- **Service tests (the bulk).** Call `create_item`, `get_item`, etc. directly with
  a `caller_id`, a dict, and a fake repository. Fast, no AWS, and they cover
  validation, ownership, and error-raising. This is where isolation cases live.
- **Handler tests (a few).** Feed a synthetic API Gateway proxy event through
  `lambda_handler` and assert on `statusCode` and the parsed body. These verify
  routing, identity extraction, and that errors map to the right status.

Aim to cover every row of the API contract plus the failure modes: missing
required field (400), bad enum (400), not-found (404), and **cross-owner access
(404, not the item)**.

## Faking DynamoDB

Two viable approaches — pick based on how much boto3 behavior you need:

1. **Fake the repository (simplest).** Since only `repository.py` touches boto3,
   inject a fake with the same methods (`get`, `put`, `query_by_owner`, ...). Your
   service tests never import boto3 at all. Best default.

2. **`moto`** (`@mock_aws`) when you want to exercise the real boto3 calls and
   table semantics — GSIs, conditional writes, `ReturnValues`. Heavier but higher
   fidelity; good for repository-level tests.

The template uses approach 1 for speed and adds a note on where `moto` fits.

## Synthetic events

A helper that builds the API Gateway proxy event shape keeps tests readable. The
critical part is `requestContext.authorizer.claims.sub` — that's the identity your
handler reads, so the helper must let each test set the caller.

```python
def make_event(method, path="/items", item_id=None, body=None, sub="user-A"):
    return {
        "httpMethod": method,
        "path": path if item_id is None else f"{path}/{item_id}",
        "pathParameters": {"id": item_id} if item_id else None,
        "body": json.dumps(body) if body is not None else None,
        "requestContext": {"authorizer": {"claims": {"sub": sub}}},
    }
```

## The isolation test (don't skip this)

The single most valuable test for an auth-scoped Lambda: user B must not be able
to reach user A's item. At the service layer it's three lines:

```python
def test_cannot_read_another_users_item(repo):
    created = create_item("user-A", {"task_name": "A's secret"})
    with pytest.raises(NotFoundError):        # not 403, not the item
        get_item("user-B", created["id"])
```

Write the same shape for update and delete. If any of them returns the item or a
403, ownership scoping is broken.

## Running

```bash
cd lambda && python -m pytest tests/ -v
```

Keep tests hermetic — no network, no real AWS credentials. If a test needs AWS,
it belongs in an integration suite, not the unit tests, and should be marked so it
doesn't run in the fast path.

See `assets/test_handler_template.py` for a ready-to-adapt starting file.
