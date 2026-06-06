data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "app" {
  count                  = var.app_instance_count
  ami                    = data.aws_ami.amazon_linux2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 python3-pip
    pip3 install flask gunicorn psycopg2-binary

    cat <<'ENVFILE' > /etc/app.env
    DB_HOST=${aws_db_instance.postgres.address}
    DB_PORT=5432
    DB_NAME=${var.db_name}
    DB_USER=${var.db_username}
    DB_PASSWORD=${var.db_password}
    APP_PORT=${var.app_port}
    ENVFILE
  EOF
  )

  tags = merge(local.tags, { Name = "${var.project}-app-${count.index + 1}" })
}
