############################################
# Lab 3: Tokyo Regional WAF (for ALB)
############################################

resource "aws_wafv2_web_acl" "chewbacca_tokyo_waf01" {
  name        = "${local.tokyo_prefix}-tokyo-waf01"
  description = "WAF for Chewbacca Tokyo ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: IP Reputation List
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
      metric_name                = "${local.tokyo_prefix}-tokyo-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Common Rule Set
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
      metric_name                = "${local.tokyo_prefix}-tokyo-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known Bad Inputs
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
      metric_name                = "${local.tokyo_prefix}-tokyo-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: SQLi Rule Set
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
      metric_name                = "${local.tokyo_prefix}-tokyo-sqli-rules"
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
      metric_name                = "${local.tokyo_prefix}-tokyo-wp-block"
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
      metric_name                = "${local.tokyo_prefix}-tokyo-rate-limit"
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
      metric_name                = "${local.tokyo_prefix}-tokyo-wordpress-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.tokyo_prefix}-tokyo-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.tokyo_tags, {
    Name = "${local.tokyo_prefix}-tokyo-waf01"
  })
}

resource "aws_wafv2_web_acl_association" "chewbacca_tokyo_waf_alb_assoc" {
  resource_arn = aws_lb.chewbacca_alb01.arn
  web_acl_arn  = aws_wafv2_web_acl.chewbacca_tokyo_waf01.arn
}
