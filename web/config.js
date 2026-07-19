// config.js: runtime configuration for the frontend.
//
// These are PLACEHOLDERS. The CI/CD pipeline (Phase 6) substitutes the real
// values from Terraform outputs during deploy, before syncing web/ to S3:
//   API_BASE_URL      <- api_invoke_url
//   COGNITO_REGION    <- aws_region
//   COGNITO_POOL_ID   <- cognito_user_pool_id
//   COGNITO_CLIENT_ID <- cognito_app_client_id
//
// Keeping them out of the HTML/JS means no rebuild is needed per environment and
// generated IDs stay out of git.
window.APP_CONFIG = {
  API_BASE_URL: "__API_BASE_URL__",
  COGNITO_REGION: "__COGNITO_REGION__",
  COGNITO_POOL_ID: "__COGNITO_POOL_ID__",
  COGNITO_CLIENT_ID: "__COGNITO_CLIENT_ID__",
};
