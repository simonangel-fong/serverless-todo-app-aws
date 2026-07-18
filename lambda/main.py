# DEPRECATED — superseded by the layered handler in lambda/src/ (Phase 2 refactor).
# This file is auth-unaware and does not implement the locked API contract
# (docs/api-contract.md). It is kept only so the current Terraform packaging
# (terraform/tf_lambda.tf, source_file=main.py, handler=main.lambda_handler)
# still plans/applies. Phase 4 rewires packaging to lambda/src/ (entry point
# handler.lambda_handler) and Phase 6 updates CI packaging; this file is removed
# then. Do not add features here — edit lambda/src/ instead.
import json
import boto3
from decimal import Decimal
import uuid
from datetime import datetime

client = boto3.client('dynamodb')
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table('todo-app-table')


def lambda_handler(event, context):

    # default response
    statusCode = 500
    response_body = {}

    try:
        # get method, path
        http_method = event['httpMethod']
        path = event['path']
        path_parameters = event.get('pathParameters')

        # Get all: /items
        if http_method == 'GET' and path == '/items':
            response = table.scan()
            items = response.get('Items', [])

            # Format each item, handling optional fields safely
            formatted_items = []
            for item in items:
                formatted_items.append({
                    'id': item.get('id'),
                    'task_name': item.get('task_name'),
                    'task_priority': item.get('task_priority', 'Medium'),
                    'task_status': item.get('task_status', 'Pending'),
                    'due_date': item.get('due_date')
                })

            statusCode = 200
            response_body["message"] = "Retrieved all items"
            response_body["data"] = formatted_items

        # Get an item: /items/{id}
        elif http_method == 'GET' and path_parameters and 'id' in path_parameters:
            item_id = path_parameters['id']

            response = table.get_item(Key={'id': item_id})
            item = response.get('Item')

            if item:
                statusCode = 200
                response_body["message"] = "Item retrieved"
                response_body["data"] = item
            else:
                statusCode = 404
                response_body["message"] = "Item not found"
                response_body["error"] = f"No item exists with ID '{item_id}'"

        # Create new: /items
        elif http_method == 'POST' and path == '/items':
            try:
                body = json.loads(event['body'])

                required_fields = ['task_name']
                missing = [
                    field for field in required_fields if field not in body or not body[field]]

                if missing:
                    statusCode = 400
                    response_body["message"] = f"Missing required field(s): {', '.join(missing)}"
                else:
                    item = {
                        # or use body['id'] if client provides
                        'id': str(uuid.uuid4()),
                        'task_name': body['task_name'],
                        'task_priority': body.get('task_priority', 'Medium'),
                        'task_status': body.get('task_status', 'Pending'),
                        'due_date': body.get('due_date', None),
                        'created_at': datetime.utcnow().isoformat()
                    }

                    table.put_item(Item=item)

                    statusCode = 201
                    response_body["message"] = "Item created"
                    response_body["data"] = item

            except json.JSONDecodeError:
                statusCode = 400
                response_body["message"] = "Invalid JSON payload"

        # Update item: /items/{id}
        elif http_method == 'PUT' and path_parameters and 'id' in path_parameters:
            item_id = path_parameters['id']

            try:
                body = json.loads(event['body'])
                update_expression = []
                expression_attribute_values = {}

                for field in ['task_name', 'task_priority', 'task_status', 'due_date']:
                    if field in body:
                        update_expression.append(f"{field} = :{field}")
                        expression_attribute_values[f":{field}"] = body[field]

                if not update_expression:
                    statusCode = 400
                    response_body["message"] = "No fields provided to update"
                else:
                    table.update_item(
                        Key={'id': item_id},
                        UpdateExpression="SET " + ", ".join(update_expression),
                        ExpressionAttributeValues=expression_attribute_values
                    )
                    statusCode = 200
                    response_body["message"] = f"Item {item_id} updated"
            except json.JSONDecodeError:
                statusCode = 400
                response_body["message"] = "Invalid JSON payload"

        # Delete item: /items/{id}
        elif http_method == 'DELETE' and path_parameters and 'id' in path_parameters:
            item_id = path_parameters['id']

            # Check if item exists
            response = table.get_item(Key={'id': item_id})
            if 'Item' not in response:
                statusCode = 404
                response_body["message"] = "Item not found"
                response_body["error"] = f"No item exists with ID '{item_id}'"
            else:
                table.delete_item(Key={'id': item_id})
                statusCode = 200
                response_body["message"] = f"Item {item_id} deleted"

        else:
            statusCode = 405
            response_body["message"] = "Method Not Allowed"
            response_body["error"] = "Method not allowed for this endpoint"

        return {
            'statusCode': statusCode,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_body)
        }

    except Exception as e:
        return {
            'statusCode': statusCode,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
