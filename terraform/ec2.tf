data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_key_pair" "app" {
  key_name   = "${var.project}-key"
  public_key = var.public_key

  tags = merge(local.tags, { Name = "${var.project}-key" })
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.app.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_cloudwatch.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Install CloudWatch agent
    yum install -y amazon-cloudwatch-agent

    # CloudWatch agent config
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
    {
      "agent": { "metrics_collection_interval": 60 },
      "metrics": {
        "namespace": "${var.project}/System",
        "metrics_collected": {
          "mem":  { "measurement": ["mem_used_percent"] },
          "disk": { "measurement": ["disk_used_percent"], "resources": ["/"] }
        },
        "append_dimensions": { "InstanceId": "$${aws:InstanceId}" }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/app.log",
                "log_group_name": "/${var.project}/app",
                "log_stream_name": "{instance_id}"
              },
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/${var.project}/system",
                "log_stream_name": "{instance_id}"
              },
              {
                "file_path": "/var/log/nginx/access.log",
                "log_group_name": "/${var.project}/access",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    CWCONFIG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
  EOF
  )

  tags = merge(local.tags, { Name = "${var.project}-app" })
}
