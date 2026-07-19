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
