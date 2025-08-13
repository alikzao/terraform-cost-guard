###############################################
# Module: baseline_ecs                        #
# Purpose: spin up an ECS cluster on Fargate   #
#           with a single Nginx task/service.  #
###############################################
# Inputs
#   - baseline_tags         (map(string))
#   - cluster_name          (string, optional)
#   - service_desired_count (number, optional)
#
# Outputs
#   - cluster_id
#   - service_name
###############################################

##############################
# 1. Variables
##############################
variable "baseline_tags" {
  description = "Common tags applied to all ECS resources in this baseline PoC"
  type        = map(string)
}

variable "cluster_name" {
  description = "Name for the ECS cluster & related resources"
  type        = string
  default     = "baseline-cluster"
}

variable "service_desired_count" {
  description = "Number of Fargate tasks to run in the service"
  type        = number
  default     = 1
}

##############################
# 2. ECS Cluster
##############################
resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
  tags = var.baseline_tags
}

##############################
# 3. IAM Role for Fargate tasks
##############################
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_exec_role" {
  name               = "${var.cluster_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.baseline_tags
}

resource "aws_iam_role_policy_attachment" "exec_policy_attachment" {
  role       = aws_iam_role.task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##############################
# 4. Task Definition (Nginx)
##############################
resource "aws_ecs_task_definition" "nginx_task" {
  family                   = "${var.cluster_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu    = "256"
  memory = "512"
  execution_role_arn = aws_iam_role.task_exec_role.arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "nginx:latest"
      cpu       = 128
      memory    = 256
      essential = true
      portMappings = [
        { containerPort = 80, hostPort = 80, protocol = "tcp" }
      ]
    }
  ])

  tags = var.baseline_tags
}

##############################
# 5. Networking (default VPC)
##############################
# Re‑use default VPC & Subnets to keep module self‑contained.

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = data.aws_vpc.default.id
}

##############################
# 6. ECS Service
##############################
resource "aws_ecs_service" "service" {
  name            = "${var.cluster_name}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [data.aws_security_group.default.id]
    assign_public_ip = false
  }

  tags = var.baseline_tags
}

##############################
# 7. Outputs
##############################
output "cluster_id" {
  description = "ID of the ECS cluster created by this module"
  value       = aws_ecs_cluster.cluster.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.service.name
}
