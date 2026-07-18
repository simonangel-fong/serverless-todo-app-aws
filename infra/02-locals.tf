# Naming convention and shared tags, defined once and derived everywhere.
#
# name_prefix is the single source of truth for resource names. It is currently
# just var.app_name (keeping existing names stable during the migration — e.g.
# the DynamoDB table stays "<app_name>-table" so relocating it into a module is a
# pure state move, not a rename/replacement). An environment component can be
# layered in later (e.g. "${var.app_name}-${var.environment}") once no stateful
# resource would be renamed by it.

locals {
  name_prefix = "${var.app_name}-${var.env}"

  default_tags = merge(var.extra_tags, {
    Project     = var.app_name
    Environment = var.env
    ManagedBy   = "terraform"
  })
}
