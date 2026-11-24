terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    key    = "todo-list/terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Permite trafico HTTP (8000) y SSH (22)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Permite PostgreSQL solo desde la instancia EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-db"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "tododb"
  username               = var.db_username
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
}

resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "todo-rds-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = "tododb"
  })
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = "LabInstanceProfile"

  user_data = <<-EOF
              #!/bin/bash
              set -e
              apt-get update -y
              apt-get install -y python3-pip python3-venv git unzip curl

              mkdir -p /opt/todo-app
              git clone ${var.github_repo_url} /opt/todo-app
              cd /opt/todo-app

              python3 -m venv venv
              ./venv/bin/pip install --upgrade pip
              ./venv/bin/pip install -r src/requirements.txt

              cat << 'SERVICE' > /etc/systemd/system/todo-api.service
              [Unit]
              Description=To-Do List FastAPI Service
              After=network.target

              [Service]
              User=root
              WorkingDirectory=/opt/todo-app
              Environment="AWS_REGION=${var.aws_region}"
              Environment="DB_SECRET_NAME=todo-rds-secret"
              Environment="APP_VERSION=v1.0.0"
              ExecStart=/opt/todo-app/venv/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000
              Restart=always

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable todo-api
              systemctl start todo-api
              EOF

  tags = {
    Name = "${var.project_name}-server"
  }

  depends_on = [aws_secretsmanager_secret_version.db_secret_val]
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "ToDo-HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alerta cuando el uso de CPU en EC2 supera el 80% durante 2 minutos"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.web.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_errors" {
  alarm_name          = "ToDo-RDSConnectionErrors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "ToDoListApp"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alerta inmediata cuando falla la lectura o escritura en RDS"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "ToDo-HighTaskLatency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TaskOperationLatency"
  namespace           = "ToDoListApp"
  period              = 60
  statistic           = "Average"
  threshold           = 500
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alerta cuando el tiempo de respuesta de /tasks supera los 500 ms"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "ToDoList-Observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web.id]]
          period  = 60
          stat    = "Average"
          region  = var.aws_region
          title   = "EC2 CPU Utilization (%)"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [["ToDoListApp", "DBConnectionErrors"]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
          title   = "Errores de Conexion RDS (Count)"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [["ToDoListApp", "TaskOperationLatency"]]
          period  = 60
          stat    = "Average"
          region  = var.aws_region
          title   = "Latencia Operaciones Tareas (ms)"
        }
      }
    ]
  })
}
