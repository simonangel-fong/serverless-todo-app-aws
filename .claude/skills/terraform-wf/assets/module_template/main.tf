# <module-name> module — <one line: what resource group this owns>.
#
# This module owns one resource group. It declares NO provider and NO backend —
# those are inherited from the root. Everything it needs comes in via variables;
# everything consumers need goes out via outputs (see outputs.tf).
#
# Naming derives from var.name_prefix so names stay consistent across the stack;
# tags come from var.tags (merged with any resource-specific Name).

locals {
  name = "${var.name_prefix}-<suffix>" # e.g. "${var.name_prefix}-table"
}

# resource "aws_<type>" "this" {
#   name = local.name
#
#   # ... resource-specific configuration, parameterized via variables ...
#
#   tags = merge(var.tags, {
#     Name = local.name
#   })
# }
