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
