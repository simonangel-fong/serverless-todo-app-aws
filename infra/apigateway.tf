# apigateway.tf

locals {
  apigw_name = "${local.name_prefix}-api"

  # The two resources routes attach to, keyed to match route.resource_key.
  apigw_resource_ids = {
    items = aws_api_gateway_resource.items.id
    item  = aws_api_gateway_resource.item.id
  }
}

# ########################################
# REST API + resources
# ########################################
resource "aws_api_gateway_rest_api" "this" {
  name        = local.apigw_name
  description = "${var.app_name} todo API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = local.apigw_name
  }
}

# /items
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "items"
}

# /items/{id}
resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.items.id
  path_part   = "{id}"
}

# ########################################
# Cognito authorizer
# ########################################
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${local.name_prefix}-cognito"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  provider_arns = [aws_cognito_user_pool.users.arn]
}

# ########################################
# Routes (methods + integrations) via for_each
# ########################################
resource "aws_api_gateway_method" "route" {
  for_each = local.apigw_routes

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = local.apigw_resource_ids[each.value.resource_key]
  http_method   = each.value.http_method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "route" {
  for_each = local.apigw_routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = local.apigw_resource_ids[each.value.resource_key]
  http_method = aws_api_gateway_method.route[each.key].http_method

  # Lambda proxy: API Gateway always POSTs the event envelope to the function
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# ########################################
# CORS preflight: one OPTIONS MOCK per resource
# ########################################
resource "aws_api_gateway_method" "options" {
  for_each = local.apigw_resource_ids

  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE" # preflight is unauthenticated by design
}

resource "aws_api_gateway_integration" "options" {
  for_each = local.apigw_resource_ids

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each = local.apigw_resource_ids

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each = local.apigw_resource_ids

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${local.lambda_allowed_origin}'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# ########################################
# Deployment + stage
# ########################################
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Redeploy whenever any route/authorizer/CORS resource changes.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.items.id,
      aws_api_gateway_resource.item.id,
      aws_api_gateway_authorizer.cognito.id,
      values(aws_api_gateway_method.route)[*].id,
      values(aws_api_gateway_integration.route)[*].id,
      values(aws_api_gateway_method.options)[*].id,
      values(aws_api_gateway_integration.options)[*].id,
      values(aws_api_gateway_integration_response.options)[*].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  stage_name    = local.apigw_stage_name
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  depends_on = [aws_api_gateway_account.this]
}

# ########################################
# Logging: account-level role + API log group
# ########################################
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.apigw_name}"
  retention_in_days = local.apigw_log_retention_days
}

data "aws_iam_policy_document" "apigw_cloudwatch_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${local.name_prefix}-apigw-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_cloudwatch_assume.json
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Account-level setting: API Gateway needs this role to write access/exec logs.
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
  depends_on          = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}

# ########################################
# Allow API Gateway to invoke the Lambda
# ########################################
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}
