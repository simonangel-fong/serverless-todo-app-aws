# s3.tf

resource "random_string" "web_bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "web" {
  bucket = "${local.web_bucket_base}-${random_string.web_bucket_suffix.result}"

  tags = {
    Name = local.web_bucket_base
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "web" {
  bucket = aws_s3_bucket.web.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt objects at rest with SSE-S3 (AES256). This is stated explicitly rather
# than relying on the account default. A customer-managed KMS key (trivy
# AWS-0132) is intentionally NOT used — the bucket holds only public static web
# assets, so a CMK's cost and key management add no value; AWS-0132 is suppressed
# in .trivyignore with that rationale.
resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block every form of public access.
resource "aws_s3_bucket_public_access_block" "web" {
  bucket = aws_s3_bucket.web.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Access is exclusively via CloudFront OAC.
resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


# ########################################
# S3 bucket policy
# ########################################
# allow ONLY this distribution to read the bucket (OAC)
data "aws_iam_policy_document" "web_bucket" {
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.web.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket.json

  # public access block
  depends_on = [aws_s3_bucket_public_access_block.web]
}

# ########################################
# Frontend content
# ########################################

locals {
  web_dir = "${path.module}/../web"

  # aws_s3_object does not infer Content-Type; map by extension so files render
  # instead of downloading. text/* served as utf-8.
  web_content_types = {
    html = "text/html; charset=utf-8"
    js   = "text/javascript; charset=utf-8"
    css  = "text/css; charset=utf-8"
    json = "application/json"
    ico  = "image/x-icon"
    png  = "image/png"
    svg  = "image/svg+xml"
  }

  # Every file under web/ except the config template (rendered separately below).
  web_files = toset([
    for f in fileset(local.web_dir, "**") : f if f != "config.js.tftpl"
  ])

  # config.js rendered once from the template with this apply's outputs.
  web_config_content = templatefile("${local.web_dir}/config.js.tftpl", {
    api_base_url      = aws_api_gateway_stage.this.invoke_url
    cognito_region    = var.aws_region
    cognito_pool_id   = aws_cognito_user_pool.users.id
    cognito_client_id = aws_cognito_user_pool_client.spa.id
  })
}

resource "aws_s3_object" "web" {
  for_each = local.web_files

  bucket       = aws_s3_bucket.web.id
  key          = each.value
  source       = "${local.web_dir}/${each.value}"
  content_type = lookup(local.web_content_types, lower(regex("[^.]+$", each.value)), "application/octet-stream")
  etag         = filemd5("${local.web_dir}/${each.value}")
}

# config.js: the rendered template. `content` changing re-uploads it on its own,
# so no separate etag is needed.
resource "aws_s3_object" "web_config" {
  bucket       = aws_s3_bucket.web.id
  key          = "config.js"
  content_type = "text/javascript; charset=utf-8"
  content      = local.web_config_content
}
