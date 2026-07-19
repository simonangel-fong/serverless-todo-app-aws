# Input contract for the module. Every variable is typed and described.
# name_prefix + tags are the two every module in the stack takes, so naming and
# tagging stay uniform. Add module-specific inputs below them.

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names in this module, e.g. \"todo-app-dev\"."
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource in this module."
  default     = {}
}

# --- module-specific inputs ------------------------------------------------- #
# variable "table_arn" {
#   type        = string
#   description = "ARN of the DynamoDB table this module needs to reference."
# }
#
# Validate constrained values so bad input fails at plan time:
# variable "runtime" {
#   type        = string
#   description = "Lambda runtime identifier."
#   default     = "python3.12"
# }
