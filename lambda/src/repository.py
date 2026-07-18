"""DynamoDB access — the only layer that knows boto3.

Keeping AWS here means the service layer is testable with a fake, and a future
migration touches one file. Table name and index come from env vars so infra
owns them.

List uses a `query` on the `owner-index` GSI (owner_id partition key), never a
`scan` — see docs/api-contract.md §4 (GET /items).
"""

import os

import boto3
from boto3.dynamodb.conditions import Key

_TABLE_NAME = os.environ.get("TABLE_NAME", "todo-app-table")
_OWNER_INDEX = os.environ.get("OWNER_INDEX", "owner-index")

_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(_TABLE_NAME)


def get(item_id):
    return _table.get_item(Key={"id": item_id}).get("Item")


def put(item):
    _table.put_item(Item=item)
    return item


def query_by_owner(owner_id):
    resp = _table.query(
        IndexName=_OWNER_INDEX,
        KeyConditionExpression=Key("owner_id").eq(owner_id),
    )
    return resp.get("Items", [])


def update(item_id, changes):
    # ExpressionAttributeNames guards against reserved words (status, name, ...).
    expr = "SET " + ", ".join(f"#{k} = :{k}" for k in changes)
    resp = _table.update_item(
        Key={"id": item_id},
        UpdateExpression=expr,
        ExpressionAttributeNames={f"#{k}": k for k in changes},
        ExpressionAttributeValues={f":{k}": v for k, v in changes.items()},
        ReturnValues="ALL_NEW",
    )
    return resp["Attributes"]


def delete(item_id):
    _table.delete_item(Key={"id": item_id})
