############################################
# Lab 3: CloudFront WAF (Edge Protection)
# Must be in us-east-1 with scope = "CLOUDFRONT"
############################################

resource "aws_wafv2_web_acl" "chewbacca_cf_waf01" {
  provider = aws.useast1

  name        = "${local.tokyo_prefix}-cf-waf01"
  description = "CloudFront WAF for Chewbacca Multi-Region"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: Block known malicious IPs
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Common attack patterns
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known bad inputs (Log4j, etc.)
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: SQL injection
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Block WordPress path probes (custom)
  # This is a Flask app — any /wp-admin, /wordpress, /wp-login, /xmlrpc request is hostile
  rule {
    name     = "BlockWordPressProbes"
    priority = 5

    action {
      block {}
    }

    statement {
      or_statement {
        statement {
          byte_match_statement {
            search_string         = "/wp-admin/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "/wordpress/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "/wp-login.php"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "/xmlrpc.php"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-wp-block"
      sampled_requests_enabled   = true
    }
  }

  # Rule 6: Rate limiting — 300 requests per 5 minutes per IP
  rule {
    name     = "RateLimitPerIP"
    priority = 6

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 300
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 7: AWS WordPress managed rule group (defense in depth)
  rule {
    name     = "AWS-AWSManagedRulesWordPressRuleSet"
    priority = 7

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesWordPressRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.tokyo_prefix}-cf-wordpress-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.tokyo_prefix}-cf-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.tokyo_prefix}-cf-waf01"
  })
}
