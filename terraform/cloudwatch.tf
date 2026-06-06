# ── Log Groups ────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/app"
  retention_in_days = 30
  tags              = merge(local.tags, { Name = "${var.project}-app-logs" })
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/${var.project}/system"
  retention_in_days = 30
  tags              = merge(local.tags, { Name = "${var.project}-system-logs" })
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/${var.project}/access"
  retention_in_days = 30
  tags              = merge(local.tags, { Name = "${var.project}-access-logs" })
}

# ── EC2 IAM Role for CloudWatch ───────────────────────────────────────────────

resource "aws_iam_role" "ec2_cloudwatch" {
  name = "${var.project}-ec2-cloudwatch-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_cloudwatch" {
  name = "${var.project}-ec2-cloudwatch-profile"
  role = aws_iam_role.ec2_cloudwatch.name
}

# ── Dashboard 1: Infrastructure ───────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${var.project}-infrastructure"

  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "text",
      "x": 0, "y": 0, "width": 24, "height": 1,
      "properties": { "markdown": "## Infrastructure Metrics" }
    },
    {
      "type": "metric",
      "x": 0, "y": 1, "width": 8, "height": 6,
      "properties": {
        "title": "EC2 CPU Utilization",
        "region": "${var.aws_region}",
        "metrics": [["AWS/EC2", "CPUUtilization", "InstanceId", "${aws_instance.app.id}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 1, "width": 8, "height": 6,
      "properties": {
        "title": "EC2 Memory Usage (%)",
        "region": "${var.aws_region}",
        "metrics": [["${var.project}/System", "mem_used_percent", "InstanceId", "${aws_instance.app.id}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 16, "y": 1, "width": 8, "height": 6,
      "properties": {
        "title": "EC2 Disk Usage (%)",
        "region": "${var.aws_region}",
        "metrics": [["${var.project}/System", "disk_used_percent", "InstanceId", "${aws_instance.app.id}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 7, "width": 8, "height": 6,
      "properties": {
        "title": "RDS CPU Utilization",
        "region": "${var.aws_region}",
        "metrics": [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${aws_db_instance.postgres.identifier}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 7, "width": 8, "height": 6,
      "properties": {
        "title": "RDS Database Connections",
        "region": "${var.aws_region}",
        "metrics": [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${aws_db_instance.postgres.identifier}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 16, "y": 7, "width": 8, "height": 6,
      "properties": {
        "title": "RDS Free Storage (GB)",
        "region": "${var.aws_region}",
        "metrics": [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "${aws_db_instance.postgres.identifier}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    }
  ]
}
EOF
}

# ── Dashboard 2: Application ──────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${var.project}-application"

  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "text",
      "x": 0, "y": 0, "width": 24, "height": 1,
      "properties": { "markdown": "## Application Metrics" }
    },
    {
      "type": "metric",
      "x": 0, "y": 1, "width": 8, "height": 6,
      "properties": {
        "title": "Request Count",
        "region": "${var.aws_region}",
        "metrics": [["${var.project}/App", "RequestCount"]],
        "period": 60, "stat": "Sum", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 1, "width": 8, "height": 6,
      "properties": {
        "title": "Error Count (4xx + 5xx)",
        "region": "${var.aws_region}",
        "metrics": [["${var.project}/App", "ErrorCount"]],
        "period": 60, "stat": "Sum", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 16, "y": 1, "width": 8, "height": 6,
      "properties": {
        "title": "Avg Latency (ms)",
        "region": "${var.aws_region}",
        "metrics": [["${var.project}/App", "Latency"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 7, "width": 8, "height": 6,
      "properties": {
        "title": "ALB Request Count",
        "region": "${var.aws_region}",
        "metrics": [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${aws_lb.main.arn_suffix}"]],
        "period": 60, "stat": "Sum", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 8, "y": 7, "width": 8, "height": 6,
      "properties": {
        "title": "ALB 5xx Errors",
        "region": "${var.aws_region}",
        "metrics": [["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", "${aws_lb.main.arn_suffix}"]],
        "period": 60, "stat": "Sum", "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 16, "y": 7, "width": 8, "height": 6,
      "properties": {
        "title": "ALB Target Response Time (s)",
        "region": "${var.aws_region}",
        "metrics": [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${aws_lb.main.arn_suffix}"]],
        "period": 60, "stat": "Average", "view": "timeSeries"
      }
    }
  ]
}
EOF
}
