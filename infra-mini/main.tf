
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-2"
}

# Red predeterminada de AWS
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Repositorio Docker existente en ECR
data "aws_ecr_repository" "app" {
  name = "reto-java-ecs"
}

# Permitir acceso publico al puerto 8080
resource "aws_security_group" "app" {
  name_prefix = "reto-java-mini-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
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

# Rol IAM utilizado por ECS para obtener imagenes ECR
resource "aws_iam_role" "execution" {
  name = "reto-java-mini-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"

      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Cluster ECS
resource "aws_ecs_cluster" "app" {
  name = "reto-java-mini"
}

# Definicion de la tarea Java
resource "aws_ecs_task_definition" "app" {
  family                   = "reto-java-mini"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.execution.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${data.aws_ecr_repository.app.repository_url}:demo-20261113201049"
    essential = true

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
  }])
}

# Servicio ECS Fargate
resource "aws_ecs_service" "app" {
  name            = "reto-java-mini"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn

  # Apagado por defecto para ahorrar creditos AWS
  desired_count = 0

  launch_type = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution
  ]

  # No sobrescribir cambios realizados por GitHub Actions
  # ni encender ECS cuando se haya apagado manualmente.
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }
}
