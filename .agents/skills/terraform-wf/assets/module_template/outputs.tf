# Output contract: expose only what a CONSUMER (another module or the root) needs
# to wire to this module. Describe each accurately — the description is docs.
# Don't dump every attribute; outputs are surface area.

# output "name" {
#   description = "The resource's name, for downstream references."
#   value       = aws_<type>.this.name
# }
#
# output "arn" {
#   description = "The resource's ARN, e.g. for an IAM policy scope."
#   value       = aws_<type>.this.arn
# }
#
# Mark sensitive outputs so they don't leak into logs:
# output "secret_value" {
#   value     = aws_<type>.this.secret
#   sensitive = true
# }
