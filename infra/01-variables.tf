# variables.tf

# ########################################
# Metadata
# ########################################
variable "app_name" {
  type        = string
  description = "Application name; used as the resource name prefix. Lowercase alphanumeric and hyphens only."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.app_name))
    error_message = "app_name must contain only lowercase letters, digits, and hyphens."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for the provider."
  default     = "ca-central-1"
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags merged into the default tag set applied to every resource."
  default     = {}
}

variable "env" {
  type        = string
  description = "Deployment environment name; part of the resource name prefix."
  default     = "dev"
}

# ########################################
# Cloudflare DNS
# ########################################
variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with DNS edit + zone read for the frontend zone. Supply via TF_VAR_cloudflare_api_token; never commit it."
  sensitive   = true
}

# ########################################
# CI/CD deploy role (GitHub OIDC)
# ########################################
variable "state_bucket" {
  type        = string
  description = "Name of the S3 bucket holding Terraform state, so the deploy role can be granted access to it. Should match the bucket in backend.hcl."
  default     = ""
}


