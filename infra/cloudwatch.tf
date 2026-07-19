# cloudwatch.tf

locals {
  cloudwatch_alarm_dimensions = {
    lambda   = { FunctionName = aws_lambda_function.api.function_name }
    api      = { ApiName = aws_api_gateway_rest_api.this.name, Stage = aws_api_gateway_stage.this.stage_name }
    dynamodb = { TableName = aws_dynamodb_table.todo.name }
  }
}

# ########################################
# SNS topic (alarm target)
# ########################################
resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"

  # Encrypt topic contents at rest with the AWS-managed SNS key (no cost, no key
  # management). Satisfies tfsec/trivy AWS-0095.
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${local.name_prefix}-alarms"
  }
}

# ########################################
# Metric alarms (one per failure signal)
# ########################################
resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.cloudwatch_alarms

  alarm_name          = "${local.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = local.cloudwatch_alarm_dimensions[each.value.dimensions_key]

  # Missing data is normal here (no errors = no datapoints); don't alarm on it.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name = "${local.name_prefix}-${each.key}"
  }
}

# ########################################
# Dashboard
# ########################################
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.api.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.api.function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.api.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "Average" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.this.name, "Stage", aws_api_gateway_stage.this.stage_name],
            ["AWS/ApiGateway", "4XXError", "ApiName", aws_api_gateway_rest_api.this.name, "Stage", aws_api_gateway_stage.this.stage_name],
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.this.name, "Stage", aws_api_gateway_stage.this.stage_name],
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.this.name, "Stage", aws_api_gateway_stage.this.stage_name, { stat = "Average" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.todo.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.todo.name],
            ["AWS/DynamoDB", "ThrottledRequests", "TableName", aws_dynamodb_table.todo.name],
          ]
        }
      },
    ]
  })
}
