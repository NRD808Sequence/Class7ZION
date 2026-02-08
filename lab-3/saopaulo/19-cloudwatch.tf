############################################
# Lab 3: São Paulo CloudWatch Alarms + SNS
# Matches Tokyo alarm coverage (minus RDS — APPI)
############################################

#-----------------------------------------------------------------------------
# SNS Topic + Email Subscription
#-----------------------------------------------------------------------------

resource "aws_sns_topic" "liberdade_sns_topic01" {
  name = "${local.saopaulo_prefix}-alb-incidents"

  tags = local.saopaulo_tags
}

resource "aws_sns_topic_subscription" "liberdade_sns_sub01" {
  topic_arn = aws_sns_topic.liberdade_sns_topic01.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

#-----------------------------------------------------------------------------
# ALB 5xx Alarm
#-----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "liberdade_alb_5xx_alarm" {
  alarm_name          = "${local.saopaulo_prefix}-alb-5xx-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.liberdade_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.liberdade_sns_topic01.arn]
  ok_actions    = [aws_sns_topic.liberdade_sns_topic01.arn]

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_prefix}-alarm-alb-5xx"
  })
}

#-----------------------------------------------------------------------------
# ALB Unhealthy Hosts Alarm
#-----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "liberdade_alb_unhealthy_alarm" {
  alarm_name          = "${local.saopaulo_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1

  dimensions = {
    TargetGroup  = aws_lb_target_group.liberdade_tg01.arn_suffix
    LoadBalancer = aws_lb.liberdade_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.liberdade_sns_topic01.arn]
  ok_actions    = [aws_sns_topic.liberdade_sns_topic01.arn]

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_prefix}-alarm-unhealthy-hosts"
  })
}

#-----------------------------------------------------------------------------
# App DB Connection Errors Alarm (custom metric from Flask app)
#-----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "liberdade_db_conn_alarm" {
  alarm_name          = "${local.saopaulo_prefix}-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Chewbacca/RDSApp"
  period              = 300
  statistic           = "Sum"
  threshold           = 3

  alarm_actions = [aws_sns_topic.liberdade_sns_topic01.arn]

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_prefix}-alarm-db-fail"
  })
}
