############################################
# Lab 3: São Paulo Origin DNS Record
# CloudFront failover origin uses this FQDN so the
# ALB's ACM wildcard cert (*.keepuneat.click) matches.
# Without this, https-only origin protocol gets SSL 502.
############################################

resource "aws_route53_record" "liberdade_origin_dns" {
  zone_id = data.aws_route53_zone.chewbacca_zone.zone_id
  name    = "origin-saopaulo.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.liberdade_alb01.dns_name
    zone_id                = aws_lb.liberdade_alb01.zone_id
    evaluate_target_health = true
  }
}
