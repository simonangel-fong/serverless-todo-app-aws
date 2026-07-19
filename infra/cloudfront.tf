# cloudfront.tf

locals {
  cloudfront_origin_id = "s3-${aws_s3_bucket.web.id}"
}

# ########################################
# Origin Access Control
# ########################################
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${local.name_prefix}-web-oac"
  description                       = "OAC for the ${var.app_name} frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ########################################
# Cache policy — short TTL
# ########################################
resource "aws_cloudfront_cache_policy" "short_ttl" {
  name        = "${local.name_prefix}-short-ttl"
  default_ttl = 60
  min_ttl     = 0
  max_ttl     = 300

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# ########################################
# ACM certificate
# ########################################
data "aws_acm_certificate" "frontend" {
  provider    = aws.us_east_1
  domain      = local.acm_certificate_domain
  types       = ["AMAZON_ISSUED"]
  statuses    = ["ISSUED"]
  most_recent = true
}

# ########################################
# Distribution
# ########################################
resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = local.cloudfront_price_class
  comment             = "${local.name_prefix} frontend"

  # Custom domain
  aliases = [local.cloudfront_domain]

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = local.cloudfront_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  default_cache_behavior {
    target_origin_id       = local.cloudfront_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.short_ttl.id
  }

  # S3 returns 403 for a missing key. 
  # Serve index.html with 200.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Existing ACM cert (us-east-1)
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.frontend.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${local.name_prefix}-web"
  }
}
