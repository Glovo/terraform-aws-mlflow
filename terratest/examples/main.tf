provider "aws" {
  region  = "eu-west-1"
  version = "~> 3.10"
}

resource "random_id" "id" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "mlflow-terratest"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = "ran${random_id.id.hex}dom"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.70.0"

  name               = "mlflow-${random_id.id.hex}"
  cidr               = "10.0.0.0/16"
  azs                = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  database_subnets   = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
  enable_nat_gateway = true

  tags = {
    "built-using" = "terratest"
    "env"         = "test"
  }
}

variable "is_private" {
  type = bool
}

variable "artifact_bucket_id" {
  default = null
}

module "mlflow" {
  source = "../../"

  unique_name = "mlflow-terratest-${random_id.id.hex}"
  tags = {
    "owner" = "terratest"
  }
  vpc_id                            = module.vpc.vpc_id
  database_subnet_ids               = module.vpc.database_subnets
  service_subnet_ids                = module.vpc.private_subnets
  load_balancer_subnet_ids          = var.is_private ? module.vpc.private_subnets : module.vpc.public_subnets
  load_balancer_ingress_cidr_blocks = var.is_private ? [module.vpc.vpc_cidr_block] : ["0.0.0.0/0"]
  load_balancer_is_internal         = var.is_private
  artifact_bucket_id                = var.artifact_bucket_id
  database_password_secret_arn      = aws_secretsmanager_secret_version.db_password.secret_id
  database_skip_final_snapshot      = true
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = module.mlflow.load_balancer_arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = module.mlflow.load_balancer_target_group_id
    type             = "forward"
  }
}

# Outputs for Terratest to use
output "load_balancer_dns_name" {
  value = module.mlflow.load_balancer_dns_name
}

output "artifact_bucket_id" {
  value = module.mlflow.artifact_bucket_id
}
