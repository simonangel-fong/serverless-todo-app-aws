# outputs.tf

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
