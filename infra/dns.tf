# dns.tf

data "cloudflare_zone" "frontend" {
  filter = {
    name = local.dns_zone_name
  }
}

resource "cloudflare_dns_record" "frontend" {
  zone_id = data.cloudflare_zone.frontend.zone_id
  name    = local.cloudfront_domain
  type    = "CNAME"
  content = aws_cloudfront_distribution.web.domain_name
  proxied = false
  ttl     = 300 # seconds; a real TTL
  comment = "Todo App AWS DNS"
}
