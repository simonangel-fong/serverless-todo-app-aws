"""Service-layer tests: plain function calls against a fake repository.

Covers validation, defaults, ownership scoping, and the isolation cases that
matter most for an auth-scoped API.
"""

import pytest

import service
from errors import NotFoundError, ValidationError


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
    monkeypatch.setattr(service, "repository", fake)
    return fake


# --- create ---------------------------------------------------------------- #
def test_create_requires_task_name(repo):
    with pytest.raises(ValidationError):
        service.create_item("user-A", {})


def test_create_rejects_bad_enum(repo):
    with pytest.raises(ValidationError):
        service.create_item("user-A", {"task_name": "x", "task_priority": "URGENT"})


def test_create_stamps_owner_from_caller_not_body(repo):
    item = service.create_item("user-A", {"task_name": "x", "owner_id": "user-EVIL"})
    assert item["owner_id"] == "user-A"
    assert item["task_status"] == "Pending"   # default applied
    assert item["task_priority"] == "Medium"  # default applied
    assert "created_at" in item and item["id"]


# --- list ------------------------------------------------------------------ #
def test_list_returns_only_callers_items(repo):
    service.create_item("user-A", {"task_name": "a1"})
    service.create_item("user-A", {"task_name": "a2"})
    service.create_item("user-B", {"task_name": "b1"})
    assert len(service.list_items("user-A")) == 2
    assert len(service.list_items("user-B")) == 1


# --- get / ownership ------------------------------------------------------- #
def test_get_missing_id_raises_not_found(repo):
    with pytest.raises(NotFoundError):
        service.get_item("user-A", "nope")


def test_cannot_read_another_users_item(repo):
    created = service.create_item("user-A", {"task_name": "A's secret"})
    with pytest.raises(NotFoundError):        # 404, not 403, not the item
        service.get_item("user-B", created["id"])


# --- update ---------------------------------------------------------------- #
def test_update_empty_body_raises_validation(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    with pytest.raises(ValidationError):
        service.update_item("user-A", created["id"], {})


def test_update_missing_id_raises_not_found(repo):
    with pytest.raises(NotFoundError):        # no blind upsert
        service.update_item("user-A", "nope", {"task_name": "x"})


def test_update_returns_updated_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    updated = service.update_item("user-A", created["id"], {"task_status": "Completed"})
    assert updated["task_status"] == "Completed"


def test_cannot_update_another_users_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    with pytest.raises(NotFoundError):
        service.update_item("user-B", created["id"], {"task_name": "hacked"})


# --- delete ---------------------------------------------------------------- #
def test_delete_missing_id_raises_not_found(repo):
    with pytest.raises(NotFoundError):
        service.delete_item("user-A", "nope")


def test_cannot_delete_another_users_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    with pytest.raises(NotFoundError):
        service.delete_item("user-B", created["id"])


def test_delete_removes_owned_item(repo):
    created = service.create_item("user-A", {"task_name": "A"})
    service.delete_item("user-A", created["id"])
    with pytest.raises(NotFoundError):
        service.get_item("user-A", created["id"])
