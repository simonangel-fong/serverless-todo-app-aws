# Responses & errors

Inconsistent responses are the most common Lambda smell and the hardest to fix
after the fact. The cure is two small pieces: **one response builder** and **one
error taxonomy** with a single error→status mapping.

## The response envelope

Pick one body shape and use it everywhere — success and error. A widely useful
default:

```jsonc
{
  "message": "human-readable string",  // always
  "data":    {} | [],                  // on success that returns a resource
  "error":   "detail string"           // on error responses
}
```

Follow the project's contract if it defines the envelope; otherwise this is a
sensible default. The important property is that the client can parse **the same
shape** for every response.

```python
# responses.py
import json

CORS_HEADERS = {
    "Content-Type": "application/json",
    # Prefer the frontend's real origin over "*" for an authenticated API;
    # wire it from an env var so infra and code don't drift.
    "Access-Control-Allow-Origin": os.environ.get("ALLOWED_ORIGIN", "*"),
}

def response(status, message, data=None, error=None):
    body = {"message": message}
    if data is not None:
        body["data"] = data
    if error is not None:
        body["error"] = error
    return {
        "statusCode": status,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, default=_json_default),
    }

def _json_default(o):
    # DynamoDB numbers come back as Decimal, which json can't serialize.
    from decimal import Decimal
    if isinstance(o, Decimal):
        return int(o) if o % 1 == 0 else float(o)
    raise TypeError(f"Not serializable: {type(o)}")
```

The `Decimal` handling matters specifically for DynamoDB: numeric attributes come
back as `Decimal` and a plain `json.dumps` raises. Handle it once, here.

## The error taxonomy

Model expected failures as typed exceptions the service raises. The handler
catches the base class and maps to a status in one place — so the same failure
class always yields the same status, everywhere.

```python
# errors.py
class AppError(Exception):
    """Base for expected, client-facing failures."""

class ValidationError(AppError):   # -> 400
    pass

class NotFoundError(AppError):     # -> 404
    pass

class ConflictError(AppError):     # -> 409  (optional; use if you need it)
    pass

_STATUS = {
    ValidationError: 400,
    NotFoundError: 404,
    ConflictError: 409,
}

def to_status(err):
    return _STATUS.get(type(err), 500)
```

The service raises these; the handler does `except AppError as e: return
response(to_status(e), str(e))` (see `structure.md`). Anything not derived from
`AppError` is a genuine bug and falls through to the last-resort 500.

## Status-code discipline

- **200** — successful GET / PUT / DELETE.
- **201** — successful create (POST).
- **400** — validation failure, malformed JSON, empty update set.
- **401** — missing/invalid auth. With an API Gateway authorizer this is usually
  returned by the **gateway**, before your Lambda runs — you don't emit it.
- **404** — not found, **or** found-but-not-owned (see the ownership rule).
- **405** — method not allowed on the resource.
- **500** — unexpected error only. Never use 500 for an expected, client-caused
  failure — that's what the typed errors are for.

## The ownership 404

When an item exists but belongs to another caller, returning **404** (not 403)
avoids leaking that the id exists. Enforce it in the service by treating
"not found" and "not yours" identically:

```python
item = repository.get(item_id)
if item is None or item["owner_id"] != caller_id:
    raise NotFoundError(f"No item exists with ID '{item_id}'")
```

## Returning the resource consistently

If create and get return the resource in `data`, update should too. For DynamoDB,
`update_item(..., ReturnValues="ALL_NEW")` gives you the updated item without a
second read:

```python
def update(item_id, changes):
    resp = table.update_item(
        Key={"id": item_id},
        UpdateExpression="SET " + ", ".join(f"#{k} = :{k}" for k in changes),
        ExpressionAttributeNames={f"#{k}": k for k in changes},
        ExpressionAttributeValues={f":{k}": v for k, v in changes.items()},
        ReturnValues="ALL_NEW",
    )
    return resp["Attributes"]
```

(`ExpressionAttributeNames` avoids collisions with DynamoDB reserved words like
`status` and `name`.)
