data "aws_region" "current" {}

resource "aws_iam_role" "ecs_task" {
  name = "${var.unique_name}-ecs-task"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role" "ecs_execution" {
  name = "${var.unique_name}-ecs-execution"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_execution.name
}

resource "aws_security_group" "ecs_service" {
  name = "${var.unique_name}-ecs-service"
  tags = local.tags

  vpc_id = var.vpc_id

  ingress {
    from_port       = local.service_port
    to_port         = local.service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "mlflow" {
  name              = "/aws/ecs/${var.unique_name}"
  retention_in_days = var.service_log_retention_in_days
  tags              = local.tags
}

resource "aws_ecs_cluster" "mlflow" {
  name = var.unique_name
  tags = local.tags
}

resource "aws_ecs_task_definition" "mlflow" {
  family = var.unique_name
  tags   = local.tags
  container_definitions = jsonencode(concat([
    {
      name      = "mlflow"
      image     = "larribas/mlflow:${var.service_image_tag}"
      essential = true

      # As of version 1.9.1, MLflow doesn't support specifying the backend store uri as an environment variable. ECS doesn't allow evaluating secret environment variables from within the command. Therefore, we are forced to override the entrypoint and assume the docker image has a shell we can use to interpolate the secret at runtime.
      entryPoint = ["sh", "-c"]
      command = [
        "/bin/sh -c \"mlflow server --host=0.0.0.0 --port=${local.service_port} --default-artifact-root=s3://${local.artifact_bucket_id}${var.artifact_bucket_path} --backend-store-uri=mysql+pymysql://${aws_rds_cluster.backend_store.master_username}:`echo -n $DB_PASSWORD`@${aws_rds_cluster.backend_store.endpoint}:${aws_rds_cluster.backend_store.port}/${aws_rds_cluster.backend_store.database_name} --gunicorn-opts '${var.gunicorn_opts}' \""
      ]
      portMappings = [{ containerPort = local.service_port }]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = data.aws_secretsmanager_secret.db_password.arn
        },
      ]
      logConfiguration = {
        logDriver     = "awslogs"
        secretOptions = null
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mlflow.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "cis"
        }
      }
    },
  ], var.service_sidecar_container_definitions))

  network_mode             = "awsvpc"
  task_role_arn            = aws_iam_role.ecs_task.arn
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.service_cpu
  memory                   = var.service_memory
}

resource "aws_ecs_service" "mlflow" {
  name             = var.unique_name
  cluster          = aws_ecs_cluster.mlflow.id
  task_definition  = aws_ecs_task_definition.mlflow.arn
  desired_count    = 2
  launch_type      = "FARGATE"
  platform_version = "1.4.0"


  network_configuration {
    subnets         = var.service_subnet_ids
    security_groups = [aws_security_group.ecs_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mlflow.arn
    container_name   = "mlflow"
    container_port   = local.service_port
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb.mlflow,
  ]
}

resource "aws_appautoscaling_target" "mlflow" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.mlflow.name}/${aws_ecs_service.mlflow.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  max_capacity       = var.service_max_capacity
  min_capacity       = var.service_min_capacity
}

resource "aws_security_group" "lb" {
  name   = "${var.unique_name}-lb"
  tags   = local.tags
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "lb_ingress_http" {
  description       = "Only allow load balancer to reach the ECS service on the right port"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.load_balancer_ingress_cidr_blocks
  security_group_id = aws_security_group.lb.id
}

resource "aws_security_group_rule" "lb_ingress_https" {
  description       = "Only allow load balancer to reach the ECS service on the right port"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.load_balancer_ingress_cidr_blocks
  security_group_id = aws_security_group.lb.id
}

resource "aws_security_group_rule" "lb_egress" {
  description              = "Only allow load balancer to reach the ECS service on the right port"
  type                     = "egress"
  from_port                = local.service_port
  to_port                  = local.service_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id
  security_group_id        = aws_security_group.lb.id
}

resource "aws_lb" "mlflow" {
  name               = var.unique_name
  tags               = local.tags
  internal           = var.load_balancer_is_internal ? true : false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = var.load_balancer_subnet_ids
}

resource "aws_lb_target_group" "mlflow" {
  name        = var.unique_name
  port        = local.service_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol = "HTTP"
    matcher  = "200-202"
    path     = "/health"
  }
}

