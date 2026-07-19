# Structure: the three layers

The goal is a handler you can read top-to-bottom in ten seconds and logic you can
test without constructing AWS event shapes.

## Layer responsibilities

**Handler** — the only layer that knows about the API Gateway event shape.
It parses the event, extracts the caller identity once, dispatches to the right
service function, and formats the return into an HTTP response. It contains no
business rules and no DynamoDB calls.

**Service** — the business logic. Takes plain arguments (a `caller_id`, a parsed
body dict, a path id), validates, enforces ownership/rules, calls the data layer,
and returns plain Python (a dict, a list) or **raises a typed error**. It never
sees `event` and never builds an HTTP response. This is what your unit tests call
directly.

**Data / repository** — the only layer that imports and calls `boto3`. Thin
wrappers like `get(id)`, `put(item)`, `query_by_owner(owner_id)`,
`update(id, changes)`, `delete(id)`. Keeping boto3 in one place means tests can
substitute a fake, and a future migration touches one file.

## One file vs. a package

Match the ceremony to the size:

- **Small Lambda (a few routes):** one `handler.py` with three clearly commented
  sections (or three functions). Don't create a package for 60 lines.
- **Larger Lambda:** split into `handler.py`, `service.py`, `repository.py` under
  `src/`, with `tests/` alongside. The layout the todo project targets:

  ```
  lambda/
    src/
      handler.py       # routing + response formatting
      service.py       # business logic, validation calls, ownership rules
      repository.py    # DynamoDB access
      errors.py        # typed error classes (see responses.md)
    tests/
      test_service.py
      test_handler.py
    requirements.txt
  ```

## Handler dispatch

Dispatch on method + whether there's a path id. Keep each branch to a single
service call plus a `response(...)`. Read identity **once** at the top.

```python
import json
from service import list_items, get_item, create_item, update_item, delete_item
from responses import response
from errors import AppError, to_status
from logging_setup import get_logger

log = get_logger()

def lambda_handler(event, context):
    request_id = getattr(context, "aws_request_id", "-")
    method = event["httpMethod"]
    path_params = event.get("pathParameters") or {}
    item_id = path_params.get("id")

    # Identity comes from the authorizer, never the body.
    claims = event["requestContext"]["authorizer"]["claims"]
    caller_id = claims["sub"]

    log.info("request", extra={"request_id": request_id,
                               "method": method, "item_id": item_id})

    try:
        body = json.loads(event["body"]) if event.get("body") else {}

        if method == "GET" and item_id:
            return response(200, "Item retrieved", get_item(caller_id, item_id))
        if method == "GET":
            return response(200, "Retrieved all items", list_items(caller_id))
        if method == "POST":
            return response(201, "Item created", create_item(caller_id, body))
        if method == "PUT" and item_id:
            return response(200, "Item updated", update_item(caller_id, item_id, body))
        if method == "DELETE" and item_id:
            delete_item(caller_id, item_id)
            return response(200, f"Item {item_id} deleted")
        return response(405, "Method Not Allowed")

    except json.JSONDecodeError:
        return response(400, "Invalid JSON payload")
    except AppError as e:
        return response(to_status(e), str(e))
    except Exception:
        log.exception("unhandled", extra={"request_id": request_id})
        return response(500, "Internal server error")
```

Notes:

- `json.loads` is inside the `try` so a bad body becomes a clean `400`, not a 500.
- Expected failures (validation, not-found) are **typed errors** raised by the
  service and mapped to status codes in one place. See `responses.md`.
- The bare `except Exception` is the last resort: it logs with a stack trace and
  returns a generic 500 — it never leaks internals in the body.

## Threading identity through

`caller_id` is an ordinary argument to every service function — that's what makes
ownership testable:

```python
# service.py
def get_item(caller_id, item_id):
    item = repository.get(item_id)
    if item is None or item["owner_id"] != caller_id:
        raise NotFoundError(f"No item exists with ID '{item_id}'")
    return item

def list_items(caller_id):
    return repository.query_by_owner(caller_id)   # not scan()

def create_item(caller_id, body):
    validate_create(body)                          # see validation.md
    item = {
        "id": str(uuid.uuid4()),
        "owner_id": caller_id,                      # from token, not body
        "created_at": datetime.now(timezone.utc).isoformat(),
        "task_name": body["task_name"],
        "task_priority": body.get("task_priority", "Medium"),
        "task_status": body.get("task_status", "Pending"),
        "due_date": body.get("due_date"),
    }
    repository.put(item)
    return item
```

Because ownership lives in the service and `caller_id` is just a parameter, an
isolation test is a plain function call: create as user A, then
`get_item("user-B", id)` and assert it raises `NotFoundError`.
