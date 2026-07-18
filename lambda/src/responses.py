"""The single response builder — every response goes through here.

Body envelope (per the locked API contract, docs/api-contract.md §2):
    { "message": str, "data"?: ..., "error"?: str }

CORS origin is restricted to the frontend origin via the ALLOWED_ORIGIN env var
(not "*"), because the API is authenticated. Infra wires the same value so code
and gateway don't drift.
"""

import json
import os
from decimal import Decimal

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": os.environ.get("ALLOWED_ORIGIN", "*"),
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
}


def _json_default(o):
    # DynamoDB numbers come back as Decimal, which json.dumps can't serialize.
    if isinstance(o, Decimal):
        return int(o) if o % 1 == 0 else float(o)
    raise TypeError(f"Not serializable: {type(o)}")


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
