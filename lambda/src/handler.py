"""API Gateway (proxy integration) entry point — thin routing + response
formatting only. No business rules, no boto3.

Implements the locked contract in docs/api-contract.md. Identity comes from the
Cognito authorizer claims, never the body. OPTIONS (CORS preflight) is handled
by API Gateway (MOCK integration), so it never reaches this Lambda.
"""

import json

import service
from errors import AppError, to_status
from logging_setup import get_logger
from responses import response

log = get_logger()


def lambda_handler(event, context):
    request_id = getattr(context, "aws_request_id", "-")
    method = event.get("httpMethod")
    path_params = event.get("pathParameters") or {}
    item_id = path_params.get("id")

    # Identity from the authorizer, never the request body.
    caller_id = event["requestContext"]["authorizer"]["claims"]["sub"]

    log.info(
        "request",
        extra={"request_id": request_id, "method": method,
               "item_id": item_id, "owner_id": caller_id},
    )

    try:
        body = json.loads(event["body"]) if event.get("body") else {}

        if method == "GET" and item_id:
            return response(200, "Item retrieved", service.get_item(caller_id, item_id))
        if method == "GET":
            return response(200, "Retrieved all items", service.list_items(caller_id))
        if method == "POST":
            return response(201, "Item created", service.create_item(caller_id, body))
        if method == "PUT" and item_id:
            return response(200, "Item updated", service.update_item(caller_id, item_id, body))
        if method == "DELETE" and item_id:
            service.delete_item(caller_id, item_id)
            return response(200, f"Item {item_id} deleted")
        return response(405, "Method Not Allowed",
                        error="Method not allowed for this endpoint")

    except json.JSONDecodeError:
        return response(400, "Invalid JSON payload", error="Request body is not valid JSON")
    except AppError as e:
        return response(to_status(e), str(e), error=str(e))
    except Exception:
        log.exception("unhandled", extra={"request_id": request_id})
        return response(500, "Internal server error")
