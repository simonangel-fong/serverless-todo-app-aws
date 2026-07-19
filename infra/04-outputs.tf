# outputs.tf

# ########################################
# DynamoDB
# ########################################
output "dynamodb_table_name" {
  description = "DynamoDB table name (for the Lambda's TABLE_NAME env var)."
  value       = aws_dynamodb_table.todo.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN (for scoping the Lambda's IAM policy)."
  value       = aws_dynamodb_table.todo.arn
}

output "dynamodb_owner_index_name" {
  description = "Name of the owner-index GSI (for the Lambda's query on owner_id)."
  value       = local.owner_index_name
}

output "dynamodb_owner_index_arn" {
  description = "ARN of the owner-index GSI (so the IAM policy can allow Query on the index)."
  value       = "${aws_dynamodb_table.todo.arn}/index/${local.owner_index_name}"
}

# ########################################
# Lambda
# ########################################
output "lambda_function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.api.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN (for the API Gateway invoke permission)."
  value       = aws_lambda_function.api.arn
}

output "lambda_invoke_arn" {
  description = "Lambda invoke ARN (for the API Gateway AWS_PROXY integration uri)."
  value       = aws_lambda_function.api.invoke_arn
}

# ########################################
# Cognito
# ########################################
output "cognito_user_pool_arn" {
  description = "Cognito user pool ARN (for the API Gateway Cognito authorizer)."
  value       = aws_cognito_user_pool.users.arn
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID (for the frontend sign-in config)."
  value       = aws_cognito_user_pool.users.id
}

output "cognito_app_client_id" {
  description = "Cognito SPA app client ID (for the frontend sign-in config)."
  value       = aws_cognito_user_pool_client.spa.id
}
