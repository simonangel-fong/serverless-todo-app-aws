# cognito.tf

locals {
  cognito_user_pool_name = "${local.name_prefix}-users"
}

# ########################################
# User Pool
# ########################################
resource "aws_cognito_user_pool" "users" {
  name = local.cognito_user_pool_name

  # Sign in with email address.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = local.cognito_password_min_length
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # self-register
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # recover via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # sign-in identifier: email, immutable
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = false
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 2048
    }
  }

  tags = {
    Name = local.cognito_user_pool_name
  }
}

# ########################################
# App Client
# ########################################
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.name_prefix}-spa"
  user_pool_id = aws_cognito_user_pool.users.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Hosted-UI / OAuth (authorization-code flow)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = local.cognito_callback_urls
  logout_urls   = local.cognito_logout_urls

  # Token lifetimes.
  refresh_token_validity = local.cognito_refresh_token_days
  access_token_validity  = local.cognito_access_token_minutes
  id_token_validity      = local.cognito_id_token_minutes

  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  prevent_user_existence_errors = "ENABLED"
}
