# # iam.tf

# locals {
#   github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
# }

# # ########################################
# # GitHub OIDC provider
# # ########################################
# data "aws_iam_openid_connect_provider" "github" {
#   url = "https://${local.github_oidc_url}"
# }

# # ########################################
# # Deploy role
# # ########################################
# data "aws_iam_policy_document" "deploy_assume" {
#   statement {
#     actions = ["sts:AssumeRoleWithWebIdentity"]
#     effect  = "Allow"

#     principals {
#       type        = "Federated"
#       identifiers = [local.github_oidc_provider_arn]
#     }

#     # Audience must be sts.amazonaws.com
#     condition {
#       test     = "StringEquals"
#       variable = "${local.github_oidc_url}:aud"
#       values   = ["sts.amazonaws.com"]
#     }

#     # Restrict to this repo's master branch and pull requests.
#     condition {
#       test     = "StringEquals"
#       variable = "${local.github_oidc_url}:sub"
#       values   = local.github_allowed_subs
#     }
#   }
# }

# resource "aws_iam_role" "deploy" {
#   name               = "${local.name_prefix}-github-deploy-role"
#   assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
# }

# # Broad managed policies covering the services infra/ manages.
# resource "aws_iam_role_policy_attachment" "deploy_managed" {
#   for_each = toset(local.deploy_managed_policy_arns)

#   role       = aws_iam_role.deploy.name
#   policy_arn = each.value
# }

# # Access to the Terraform state bucket
# data "aws_iam_policy_document" "deploy_state" {
#   statement {
#     sid       = "StateBucketList"
#     effect    = "Allow"
#     actions   = ["s3:ListBucket"]
#     resources = ["arn:aws:s3:::${var.state_bucket}"]
#   }

#   statement {
#     sid       = "StateObjectAccess"
#     effect    = "Allow"
#     actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
#     resources = ["arn:aws:s3:::${var.state_bucket}/*"]
#   }
# }

# resource "aws_iam_role_policy" "deploy_state" {
#   name   = "${local.name_prefix}-deploy-state-access"
#   role   = aws_iam_role.deploy.id
#   policy = data.aws_iam_policy_document.deploy_state.json
# }
