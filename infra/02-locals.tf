# locals.tf

locals {
  # ########################################
  # Metadata
  # ########################################
  name_prefix = "${var.app_name}-${var.env}"

  default_tags = merge(var.extra_tags, {
    Project     = var.app_name
    Environment = var.env
    ManagedBy   = "terraform"
  })

  # ########################################
  # Lambda Function
  # ########################################
  lambda_runtime            = "python3.12"
  lambda_architectures      = ["x86_64"]
  lambda_timeout            = 30
  lambda_allowed_origin     = "*"
  lambda_log_level          = "INFO"
  lambda_log_retention_days = 14

  # ########################################
  # Cognito
  # ########################################
  cognito_callback_urls = ["http://localhost:3000/"]
  cognito_logout_urls   = ["http://localhost:3000/"]

  # Refresh/access/ID token validity.
  cognito_refresh_token_days   = 30
  cognito_access_token_minutes = 60
  cognito_id_token_minutes     = 60

  # Minimum password length
  cognito_password_min_length = 8

  # ########################################
  # API Gateway
  # ########################################
  apigw_stage_name         = var.env
  apigw_log_retention_days = 14

  apigw_routes = {
    list_items  = { http_method = "GET", resource_key = "items" }
    create_item = { http_method = "POST", resource_key = "items" }
    get_item    = { http_method = "GET", resource_key = "item" }
    update_item = { http_method = "PUT", resource_key = "item" }
    delete_item = { http_method = "DELETE", resource_key = "item" }
  }

  # ########################################
  # S3 (frontend)
  # ########################################
  web_bucket_base = "${local.name_prefix}-web"

  # ########################################
  # CloudFront
  # ########################################
  # North America + Europe edge locations (cheapest).
  cloudfront_price_class = "PriceClass_100"
  cloudfront_domain      = "todo-app.arguswatcher.net"

  acm_certificate_domain = "*.arguswatcher.net"

  # Cloudflare zone that hosts cloudfront_domain (the apex, not the subdomain).
  dns_zone_name = "arguswatcher.net"


  # ########################################
  # CI/CD deploy role (GitHub OIDC)
  # ########################################
  github_repository = "simonangel-fong/serverless-todo-app-aws"
  github_oidc_url   = "token.actions.githubusercontent.com"

  # Refs allow: master, pull requests
  github_allowed_subs = [
    "repo:${local.github_repository}:ref:refs/heads/master",
    "repo:${local.github_repository}:environment:production",
    "repo:${local.github_repository}:pull_request",
    "repo:simonangel-fong/Project-Serverless-Todo-List:ref:refs/heads/master",
    "repo:simonangel-fong/Project-Serverless-Todo-List:pull_request",
    "repo:simonangel-fong/Project-Serverless-Todo-List:environment:production",
  ]

  # AWS-managed policies: services infra/ manages
  deploy_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/CloudFrontFullAccess",
    "arn:aws:iam::aws:policy/AmazonCognitoPowerUser",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
  ]

  # ########################################
  # CloudWatch alarms
  # ########################################
  cloudwatch_alarms = {
    lambda_errors = {
      namespace      = "AWS/Lambda"
      metric_name    = "Errors"
      statistic      = "Sum"
      threshold      = 1
      period         = 300
      dimensions_key = "lambda"
      description    = "Lambda function returned one or more errors."
    }
    lambda_throttles = {
      namespace      = "AWS/Lambda"
      metric_name    = "Throttles"
      statistic      = "Sum"
      threshold      = 1
      period         = 300
      dimensions_key = "lambda"
      description    = "Lambda invocations are being throttled."
    }
    api_5xx = {
      namespace      = "AWS/ApiGateway"
      metric_name    = "5XXError"
      statistic      = "Sum"
      threshold      = 1
      period         = 300
      dimensions_key = "api"
      description    = "API Gateway returned server errors (5xx)."
    }
    api_4xx = {
      namespace      = "AWS/ApiGateway"
      metric_name    = "4XXError"
      statistic      = "Sum"
      threshold      = 20
      period         = 300
      dimensions_key = "api"
      description    = "Elevated client errors (4xx) at the API."
    }
    dynamodb_throttles = {
      namespace      = "AWS/DynamoDB"
      metric_name    = "ThrottledRequests"
      statistic      = "Sum"
      threshold      = 1
      period         = 300
      dimensions_key = "dynamodb"
      description    = "DynamoDB requests are being throttled."
    }
  }
}