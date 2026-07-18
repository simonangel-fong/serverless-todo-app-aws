"""Input validation at the service boundary.

Pure functions that raise ValidationError (-> 400) before any database call.
Enum sets and required fields match the data model in docs/api-contract.md §3.
"""

from errors import ValidationError

PRIORITIES = {"High", "Medium", "Low"}
STATUSES = {"Pending", "In Progress", "Completed"}

# Fields a client may set; server owns id / owner_id / created_at.
MUTABLE_FIELDS = ("task_name", "task_priority", "task_status", "due_date")


def validate_create(body):
    name = body.get("task_name")
    if not name or not isinstance(name, str):
        raise ValidationError("task_name is required")
    _validate_optional_enums(body)


def validate_update(body):
    if not any(field in body for field in MUTABLE_FIELDS):
        raise ValidationError("No fields provided to update")
    _validate_optional_enums(body)


def _validate_optional_enums(body):
    if "task_priority" in body and body["task_priority"] not in PRIORITIES:
        raise ValidationError(f"task_priority must be one of {sorted(PRIORITIES)}")
    if "task_status" in body and body["task_status"] not in STATUSES:
        raise ValidationError(f"task_status must be one of {sorted(STATUSES)}")
