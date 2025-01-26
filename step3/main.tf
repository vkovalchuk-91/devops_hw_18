terraform {
  backend "s3"{
  bucket = "github-actions-slengpack"
  key = "terrraformECR.tfstate"
  region = "eu-central-1"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "wordpress_cluster" {
  name = "wordpress-cluster"
}

# --- IAM Policy Attachments ---
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_container_service_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_iam_role_policy_attachment" "ecs_ssm_full_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_cloudwatch_full_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# --- Security Group ---
resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-wordpress-"
  vpc_id      = "vpc-0c80e45ccf114585f" # use your VPC

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

# --- ALB ---
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = ["subnet-032cdd951f8b27757", "subnet-0912efede1e8e435b"] #use public subnet
}

# --- Target Group ---
resource "aws_lb_target_group" "wordpress_tg" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "vpc-0c80e45ccf114585f" # use your VPC
  target_type = "ip"
}

# --- Listener ---
resource "aws_lb_listener" "wordpress_http_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "wordpress_https_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:eu-central-1:571600859313:certificate/888fe5ba-e2b2-4b82-ba8e-05948b72b9a2" # use your Certificate ARN

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# --- Task Definition ---
resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "571600859313.dkr.ecr.eu-central-1.amazonaws.com/wordpress-repo:custom" # use your docker image form ECR
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = "slengpack-db-instance.cf4amqa86ky4.eu-central-1.rds.amazonaws.com"
        }
      ]
    }
  ])
}

# --- ECS Service ---
resource "aws_ecs_service" "wordpress" {
  name            = "wordpress-service"
  cluster         = aws_ecs_cluster.wordpress_cluster.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1

  launch_type = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets         = ["subnet-053b7e675d6a6d034", "subnet-0c4a63bddff0acca0"] #use private subnet
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
    container_name   = "wordpress"
    container_port   = 80
  }
}

# --- SSL Service ---
resource "aws_acm_certificate" "wp_ssl" {
  domain_name       = "slengpack.click" # Replace with your Domain name
  validation_method = "DNS"

  tags = {
    Name = "WordPress SSL"
  }
}

# --- Route 53 Service ---
resource "aws_route53_record" "wp_ssl_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wp_ssl.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = "Z01395012J3XT7EYYWFEC" # Replace with your hosted zone ID
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "wp_ssl_validation" {
  certificate_arn         = aws_acm_certificate.wp_ssl.arn
  validation_record_fqdns = [for record in aws_route53_record.wp_ssl_validation : record.fqdn]
}


resource "aws_route53_record" "wp_dns" {
  zone_id = "Z01395012J3XT7EYYWFEC" # Replace with your hosted zone ID
  name    = "slengpack.click" # Replace with your Domain name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}
