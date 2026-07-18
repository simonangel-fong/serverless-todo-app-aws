"""Handler-layer tests: drive synthetic API Gateway proxy events through
lambda_handler and assert on statusCode + parsed body. Verifies routing,
identity extraction, and error->status mapping.
"""

import json

import pytest

import handler
import service
from test_service import FakeRepo


@pytest.fixture
def repo(monkeypatch):
    fake = FakeRepo()
    monkeypatch.setattr(service, "repository", fake)
    return fake


def make_event(method, item_id=None, body=None, sub="user-A"):
    return {
        "httpMethod": method,
        "path": "/items" if item_id is None else f"/items/{item_id}",
        "pathParameters": {"id": item_id} if item_id else None,
        "body": json.dumps(body) if body is not None else None,
        "requestContext": {"authorizer": {"claims": {"sub": sub}}},
    }


class FakeContext:
    aws_request_id = "test-request-id"


def _body(resp):
    return json.loads(resp["body"])


def test_post_returns_201_with_data(repo):
    resp = handler.lambda_handler(make_event("POST", body={"task_name": "buy milk"}), FakeContext())
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


def test_get_list_returns_200_array(repo):
    handler.lambda_handler(make_event("POST", body={"task_name": "a"}), FakeContext())
    resp = handler.lambda_handler(make_event("GET"), FakeContext())
    assert resp["statusCode"] == 200
    assert isinstance(_body(resp)["data"], list)


def test_get_missing_item_returns_404(repo):
    resp = handler.lambda_handler(make_event("GET", item_id="nope"), FakeContext())
    assert resp["statusCode"] == 404


def test_get_other_users_item_returns_404(repo):
    created = _body(handler.lambda_handler(
        make_event("POST", body={"task_name": "A"}, sub="user-A"), FakeContext()))["data"]
    resp = handler.lambda_handler(
        make_event("GET", item_id=created["id"], sub="user-B"), FakeContext())
    assert resp["statusCode"] == 404


def test_put_returns_200_with_updated_data(repo):
    created = _body(handler.lambda_handler(
        make_event("POST", body={"task_name": "A"}), FakeContext()))["data"]
    resp = handler.lambda_handler(
        make_event("PUT", item_id=created["id"], body={"task_status": "Completed"}), FakeContext())
    assert resp["statusCode"] == 200
    assert _body(resp)["data"]["task_status"] == "Completed"


def test_put_missing_item_returns_404(repo):
    resp = handler.lambda_handler(
        make_event("PUT", item_id="nope", body={"task_name": "x"}), FakeContext())
    assert resp["statusCode"] == 404


def test_delete_returns_200(repo):
    created = _body(handler.lambda_handler(
        make_event("POST", body={"task_name": "A"}), FakeContext()))["data"]
    resp = handler.lambda_handler(make_event("DELETE", item_id=created["id"]), FakeContext())
    assert resp["statusCode"] == 200


def test_unknown_method_returns_405(repo):
    resp = handler.lambda_handler(make_event("PATCH", item_id="x"), FakeContext())
    assert resp["statusCode"] == 405


def test_response_has_cors_and_json_headers(repo):
    resp = handler.lambda_handler(make_event("GET"), FakeContext())
    assert resp["headers"]["Content-Type"] == "application/json"
    assert "Access-Control-Allow-Origin" in resp["headers"]
