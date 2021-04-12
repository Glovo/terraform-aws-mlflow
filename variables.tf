variable "unique_name" {
  type        = string
  description = "A unique name for this application (e.g. mlflow-team-name)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "AWS Tags common to all the resources created"
}

variable "vpc_id" {
  type        = string
  description = "AWS VPC to deploy MLflow into"
}

variable "load_balancer_subnet_ids" {
  type        = list(string)
  description = "List of subnets where the Load Balancer will be deployed"
}

variable "load_balancer_ingress_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks from where to allow traffic to the Load Balancer. With an internal LB, we've left this "
}

variable "load_balancer_is_internal" {
  type        = bool
  default     = true
  description = "By default, the load balancer is internal. This is because as of v1.9.1, MLflow doesn't have native authentication or authorization. We recommend exposing MLflow behind a VPN or using OIDC/Cognito together with the LB listener."
}

variable "service_subnet_ids" {
  type        = list(string)
  description = "List of subnets where the MLflow ECS service will be deployed (the recommendation is to use subnets that cannot be accessed directly from the Internet)"
}

variable "service_image_tag" {
  type        = string
  default     = "1.9.1"
  description = "The MLflow version to deploy. Note that this version has to be available as a tag here: https://hub.docker.com/r/larribas/mlflow"
}

variable "service_cpu" {
  type        = number
  default     = 2048
  description = "The number of CPU units reserved for the MLflow container"
}

variable "service_memory" {
  type        = number
  default     = 4096
  description = "The amount (in MiB) of memory reserved for the MLflow container"
}

variable "service_log_retention_in_days" {
  type        = number
  default     = 90
  description = "The number of days to keep logs around"
}

variable "service_sidecar_container_definitions" {
  default     = []
  description = "A list of container definitions to deploy alongside the main container. See: https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html#container_definitions"
}

variable "service_min_capacity" {
  type        = number
  default     = 2
  description = "Minimum number of instances for the ecs service. This will create an aws_appautoscaling_target that can later on be used to autoscale the MLflow instance"
}

variable "service_max_capacity" {
  type        = number
  default     = 2
  description = "Maximum number of instances for the ecs service. This will create an aws_appautoscaling_target that can later on be used to autoscale the MLflow instance"
}

variable "database_subnet_ids" {
  type        = list(string)
  description = "List of subnets where the RDS database will be deployed"
}

variable "database_password_secret_arn" {
  type        = string
  description = "The ARN of the SecretManager secret that defines the database password. It needs to be created before calling the module"
}

variable "database_min_capacity" {
  type        = number
  default     = 1
  description = "The minimum capacity for the Aurora Serverless cluster. Aurora will scale automatically in this range. See: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless.how-it-works.html"
}

variable "database_max_capacity" {
  type        = number
  default     = 1
  description = "The maximum capacity for the Aurora Serverless cluster. Aurora will scale automatically in this range. See: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless.how-it-works.html"
}

variable "database_auto_pause" {
  type        = bool
  default     = true
  description = "Pause Aurora Serverless after a given amount of time with no activity. https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless.how-it-works.html#aurora-serverless.how-it-works.pause-resume"
}

variable "database_seconds_until_auto_pause" {
  type        = number
  default     = 300
  description = "The number of seconds without activity before Aurora Serverless is paused. https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless.how-it-works.html#aurora-serverless.how-it-works.pause-resume"
}

variable "database_skip_final_snapshot" {
  type    = bool
  default = false
}

variable "artifact_bucket_id" {
  type        = string
  default     = null
  description = "If specified, MLflow will use this bucket to store artifacts. Otherwise, this module will create a dedicated bucket. When overriding this value, you need to enable the task role to access the root you specified"
}

variable "artifact_bucket_path" {
  type        = string
  default     = "/"
  description = "The path within the bucket where MLflow will store its artifacts"
}

variable "artifact_buckets_mlflow_will_read" {
  description = "A list of bucket IDs MLflow will need read access to, in order to show the stored artifacts. It accepts any valid IAM resource, including ARNs with wildcards, so you can do something like arn:aws:s3:::bucket-prefix-*"
  type        = list(string)
  default     = []
}

variable "artifact_bucket_encryption_algorithm" {
  description = "Algorithm used for encrypting the default bucket."
  type        = string
  default     = "AES256"
}

variable "artifact_bucket_encryption_key_arn" {
  description = "ARN of the key used to encrypt the bucket. Only needed if you set aws:kms as encryption algorithm."
  type        = string
  default     = null
}

variable "gunicorn_opts" {
  description = "Additional command line options forwarded to gunicorn processes (https://mlflow.org/docs/latest/cli.html#cmdoption-mlflow-server-gunicorn-opts)"
  type        = string
  default     = ""
}
