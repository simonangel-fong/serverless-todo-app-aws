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
}
