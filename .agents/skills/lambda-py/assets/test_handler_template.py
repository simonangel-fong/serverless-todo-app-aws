"""Starting-point tests for an API Gateway + DynamoDB Python Lambda.

Copy into the project's tests/ directory and adapt the imports and field names.
The design goal: service tests are plain function calls against a fake
repository, so they run instantly with no AWS. A few handler tests drive
synthetic events to check routing + status mapping.

Assumes the layout from the lambda-py skill:
    src/handler.py     -> lambda_handler(event, context)
    src/service.py     -> create_item / get_item / list_items / update_item / delete_item
    src/repository.py   -> the boto3 layer the fake below replaces
    src/errors.py       -> ValidationError, NotFoundError
Adjust the imports to match the actual module names.
"""

import json
import pytest

# from src import service, handler
# from src.errors import ValidationError, NotFoundError


# --------------------------------------------------------------------------- #
# Fake repository: same method surface as repository.py, backed by a dict.
# Inject it into the service under test (e.g. service.repository = FakeRepo()).
# --------------------------------------------------------------------------- #
class FakeRepo:
    def __init__(self):
        self.store = {}

    def get(self, item_id):
        return self.store.get(item_id)

    def put(self, item):
        self.store[item["id"]] = item
        return item

    def query_by_owner(self, owner_id):
        return [i for i in self.store.values() if i["owner_id"] == owner_id]

    def update(self, item_id, changes):
        self.store[item_id].update(changes)
        return self.store[item_id]

    def delete(self, item_id):
        self.store.pop(item_id, None)


@pytest.fixture
def repo(monkeypatch):
    fake = FakeRepo()
    # monkeypatch.setattr(service, "repository", fake)
    return fake


# --------------------------------------------------------------------------- #
# Synthetic API Gateway proxy event. `sub` is the authenticated caller.
# --------------------------------------------------------------------------- #
def make_event(method, path="/items", item_id=None, body=None, sub="user-A"):
    return {
        "httpMethod": method,
        "path": path if item_id is None else f"{path}/{item_id}",
        "pathParameters": {"id": item_id} if item_id else None,
        "body": json.dumps(body) if body is not None else None,
        "requestContext": {"authorizer": {"claims": {"sub": sub}}},
    }


class FakeContext:
    aws_request_id = "test-request-id"


# --------------------------------------------------------------------------- #
# Service-layer tests (the bulk of coverage)
# --------------------------------------------------------------------------- #
def test_create_requires_task_name(repo):
    with pytest.raises(ValidationError):
        service.create_item("user-A", {})


def test_create_stamps_owner_from_caller_not_body(repo):
    item = service.create_item("user-A", {"task_name": "x", "owner_id": "user-EVIL"})
    assert item["owner_id"] == "user-A"          # body's owner_id was ignored
    assert item["task_status"] == "Pending"       # default applied


def test_list_returns_only_callers_items(repo):
    service.create_item("user-A", {"task_name": "a1"})
    service.create_item("user-B", {"task_name": "b1"})
    assert len(service.list_items("user-A")) == 1


def test_get_missing_id_raises_not_found(repo):
    with pytest.raises(NotFoundError):
        service.get_item("user-A", "does-not-exist")


def test_cannot_read_another_users_item(repo):
    created = service.create_item("user-A", {"task_name": "A's secret"})
    with pytest.raises(NotFoundError):            # 404, not 403, not the item
        service.get_item("user-B", created["id"])


def test_cannot_update_another_users_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    with pytest.raises(NotFoundError):
        service.update_item("user-B", created["id"], {"task_name": "hacked"})


def test_cannot_delete_another_users_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    with pytest.raises(NotFoundError):
        service.delete_item("user-B", created["id"])


def test_update_empty_body_raises_validation(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    with pytest.raises(ValidationError):
        service.update_item("user-A", created["id"], {})


def test_update_returns_updated_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    updated = service.update_item("user-A", created["id"], {"task_status": "Completed"})
    assert updated["task_status"] == "Completed"


# --------------------------------------------------------------------------- #
# Handler-layer tests (routing + status mapping)
# --------------------------------------------------------------------------- #
def _body(resp):
    return json.loads(resp["body"])


def test_post_returns_201(repo):
    resp = handler.lambda_handler(
        make_event("POST", body={"task_name": "buy milk"}), FakeContext()
    )
    assert resp["statusCode"] == 201
    assert _body(resp)["data"]["task_name"] == "buy milk"


def test_post_missing_field_returns_400(repo):
    resp = handler.lambda_handler(make_event("POST", body={}), FakeContext())
    assert resp["statusCode"] == 400


def test_invalid_json_returns_400(repo):
    event = make_event("POST")
    event["body"] = "{not json"
    resp = handler.lambda_handler(event, FakeContext())
    assert resp["statusCode"] == 400


def test_get_other_users_item_returns_404(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    resp = handler.lambda_handler(
        make_event("GET", item_id=created["id"], sub="user-B"), FakeContext()
    )
    assert resp["statusCode"] == 404


def test_unknown_method_returns_405(repo):
    resp = handler.lambda_handler(make_event("PATCH", item_id="x"), FakeContext())
    assert resp["statusCode"] == 405


# --------------------------------------------------------------------------- #
# Higher-fidelity option: use moto to exercise real boto3 + a GSI.
#
#   from moto import mock_aws
#   @mock_aws
#   def test_query_uses_owner_index():
#       # create the table + owner-index GSI with boto3, then assert
#       # query_by_owner hits the index and returns only the caller's rows.
#
# Reach for this at the repository layer when you need real DynamoDB semantics
# (conditional writes, ReturnValues, GSI behavior). Keep it out of the fast
# service tests above.
# --------------------------------------------------------------------------- #
