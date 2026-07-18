"""Business logic. Takes plain arguments, enforces ownership, calls the data
layer, returns plain Python or raises a typed error. Never sees the AWS event
and never builds an HTTP response — which is what makes it directly testable.

Every function is scoped by `caller_id` (the Cognito `sub` from the token).
Ownership rule (docs/api-contract.md §1): an item that exists but isn't the
caller's is treated identically to a missing item -> NotFoundError (404, not
403) so we don't leak which ids exist.
"""

import uuid
from datetime import datetime, timezone

import repository
from errors import NotFoundError
from validation import MUTABLE_FIELDS, validate_create, validate_update


def _owned_or_404(caller_id, item_id):
    item = repository.get(item_id)
    if item is None or item.get("owner_id") != caller_id:
        raise NotFoundError(f"No item exists with ID '{item_id}'")
    return item


def list_items(caller_id):
    # query on owner-index, never scan
    return repository.query_by_owner(caller_id)


def get_item(caller_id, item_id):
    return _owned_or_404(caller_id, item_id)


def create_item(caller_id, body):
    validate_create(body)
    item = {
        "id": str(uuid.uuid4()),
        "owner_id": caller_id,  # from token, never the body
        "task_name": body["task_name"],
        "task_priority": body.get("task_priority", "Medium"),
        "task_status": body.get("task_status", "Pending"),
        "due_date": body.get("due_date"),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    repository.put(item)
    return item


def update_item(caller_id, item_id, body):
    validate_update(body)
    _owned_or_404(caller_id, item_id)  # existence + ownership before write
    changes = {k: body[k] for k in MUTABLE_FIELDS if k in body}
    return repository.update(item_id, changes)


def delete_item(caller_id, item_id):
    _owned_or_404(caller_id, item_id)
    repository.delete(item_id)
