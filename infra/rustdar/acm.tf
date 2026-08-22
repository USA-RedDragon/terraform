# us-east-1 is not a preference. CloudFront reads certificates only from that
# region, whatever region the rest of the stack lives in.
resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = "rustdar.mcswain.dev"
  validation_method = "DNS"

  tags = { Name = "rustdar.mcswain.dev" }

  lifecycle {
    create_before_destroy = true
  }
}

# Blocks until the CNAME published in dns.tf has been seen by ACM, so the
# distribution never references an unissued certificate.
resource "aws_acm_certificate_validation" "site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.acm_validation : record.name]
}
