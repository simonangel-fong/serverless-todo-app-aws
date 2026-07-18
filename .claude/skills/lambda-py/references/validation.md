# Validation

Validate at the **boundary of the service layer**, before any database call, and
turn every validation failure into a `400`. Validating in the service (not the
handler) means your unit tests exercise validation directly, and every caller —
including future ones — goes through the same checks.

Keep validation as small pure functions that raise a typed `ValidationError`
(see `responses.md` for the error classes). They take a dict and return nothing on
success.

## What to check

1. **Required fields present and non-empty.** Missing or empty → 400 naming the
   field. Empty string is usually as invalid as absent for a required field.
2. **Enums are in range.** If a field must be one of a fixed set, reject anything
   else instead of silently storing garbage.
3. **Types are right.** A `due_date` that should be an ISO string shouldn't be a
   number; a count shouldn't be a string.
4. **Server-owned fields are ignored, not trusted.** `id`, `owner_id`,
   `created_at` are set by the server. If the body contains them, drop them — do
   not let the client set them.

## Pattern

```python
# validation.py
from errors import ValidationError

PRIORITIES = {"High", "Medium", "Low"}
STATUSES = {"Pending", "In Progress", "Completed"}

def validate_create(body):
    name = body.get("task_name")
    if not name or not isinstance(name, str):
        raise ValidationError("task_name is required")
    _validate_optional_enums(body)

def validate_update(body):
    # At least one mutable field must be present, else there's nothing to do.
    mutable = {"task_name", "task_priority", "task_status", "due_date"}
    if not (mutable & body.keys()):
        raise ValidationError("No fields provided to update")
    _validate_optional_enums(body)

def _validate_optional_enums(body):
    if "task_priority" in body and body["task_priority"] not in PRIORITIES:
        raise ValidationError(f"task_priority must be one of {sorted(PRIORITIES)}")
    if "task_status" in body and body["task_status"] not in STATUSES:
        raise ValidationError(f"task_status must be one of {sorted(STATUSES)}")
```

## Create vs. update

- **Create** requires the mandatory fields and applies defaults for the optional
  ones (`task_priority` → `Medium`, `task_status` → `Pending`).
- **Update** must reject an empty change set (nothing to update → 400) and should
  only touch the fields actually present, so a partial update doesn't wipe
  unspecified fields.

## A note on validation libraries

For anything beyond a handful of fields, a schema library (pydantic, jsonschema,
marshmallow) pays off and gives clearer messages. For a small handler, hand-rolled
functions like the above keep the dependency footprint (and cold-start) small.
Choose based on the number of fields and whether the project already uses one —
don't add a dependency for three fields.
