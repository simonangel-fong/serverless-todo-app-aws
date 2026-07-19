# lambda.tf

locals {
  lambda_function_name = "${local.name_prefix}-api"
  lambda_source_dir    = "${path.module}/../lambda/src"
}

# ########################################
# Packaging
# ########################################
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = local.lambda_source_dir
  output_path = "${path.module}/../lambda/build/api.zip"
}

# ########################################
# IAM: Execution role
# ########################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Policy: Least-privilege DynamoDB access
data "aws_iam_policy_document" "lambda" {
  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      aws_dynamodb_table.todo.arn,
      "${aws_dynamodb_table.todo.arn}/index/${local.owner_index_name}",
    ]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# ########################################
# Log group
# ########################################
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = local.lambda_log_retention_days
}

# ########################################
# Lambda Function
# ########################################
resource "aws_lambda_function" "api" {
  function_name    = local.lambda_function_name
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = local.lambda_runtime
  architectures    = local.lambda_architectures
  role             = aws_iam_role.lambda.arn
  timeout          = local.lambda_timeout

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.todo.name
      OWNER_INDEX    = local.owner_index_name
      ALLOWED_ORIGIN = local.lambda_allowed_origin
      LOG_LEVEL      = local.lambda_log_level
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = {
    Name = local.lambda_function_name
  }
}
