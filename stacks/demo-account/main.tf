# ###############################################################################
# # 1. Terraform Block: Versions and Providers
# ###############################################################################
# terraform {
#     required_version = ">= 1.0"
#     required_providers {
#         aws = {
#             source  = "hashicorp/aws"
#             version = "~> 5.0"
#         }
#     }
# }
# ###############################################################################
# # 2. Provider AWS
# ###############################################################################
# provider "aws" {
#     region = "eu-central-1"
# }
# ###############################################################################
# # 3. Shared local variables
# ###############################################################################
# locals {
#   baseline_tags = {
#     Purpose = "cost-baseline-trash"
#   }
# }
# ###############################################################################
# # 3.1) At the top of the file, look for the current Amazon Linux 2 AMI
# ###############################################################################
# data "aws_ami" "amazon_linux" {
#   most_recent = true
#   owners      = ["amazon"]
#
#   filter {
#     name   = "name"
#     values = ["amzn2-ami-hvm-2.0.*-x86_64-gp2", "amzn2-ami-hvm-2.0.*-x86_64-gp3"]
#   }
#   filter {
#     name   = "architecture"
#     values = ["x86_64"]
#   }
#   filter {
#     name   = "root-device-type"
#     values = ["ebs"]
#   }
# }
# ###############################################################################
# # 4. EC2: 3 инстанса t3.micro
# ###############################################################################
# resource "aws_instance" "baseline_ec2" {
#     count         = 3
#     ami           = data.aws_ami.amazon_linux.id # Amazon Linux 2 AMI (HVM), SSD Volume Type
#     instance_type = "t3.micro"
#     tags = merge(local.baseline_tags, { Name = "baseline-ec2-${count.index + 1}" })
# }
# ###############################################################################
# # 5. EBS: 50 GB gp3 volume (not mounted)
# ###############################################################################
# resource "aws_ebs_volume" "baseline_ebs" {
#     count             = 3
#     availability_zone = aws_instance.baseline_ec2[count.index].availability_zone
#     size              = 50
#     type              = "gp3"
#     tags = merge(local.baseline_tags, { Name = "baseline-ebs-${count.index + 1}" })
# }
# ###############################################################################
# # 6. RDS: MySQL and PostgreSQL, both db.t3.micro, 20 GB, no public access
# ###############################################################################
# resource "aws_db_instance" "baseline_mysql" {
#   identifier           = "baseline-mysql"
#   engine               = "mysql"
#   instance_class       = "db.t3.micro"
#   allocated_storage    = 20
#
#   username             = "admin"
#   password             = "ChangeMe123!"
#
#   skip_final_snapshot  = true
#   publicly_accessible  = false
#
#   tags = local.baseline_tags
# }
#
# resource "aws_db_instance" "baseline_postgres" {
#   identifier           = "baseline-postgres"
#   engine               = "postgres"
#   instance_class       = "db.t3.micro"
#   allocated_storage    = 20
#   username             = "baseline_user"
#   password             = "ChangeMe123!"
#   skip_final_snapshot  = true
#   publicly_accessible  = false
#
#   tags = local.baseline_tags
# }
# ###############################################################################
# # 7. ECS + Fargate: cluster → role → task → service
# ###############################################################################
# # 7.1. Cluster
# resource "aws_ecs_cluster" "baseline" {
#   name = "baseline-cluster"
#   tags = local.baseline_tags
# }
#
# # 7.2. Role for running Fargate tasks
# resource "aws_iam_role" "ecs_task_exec_role" {
#   name = "baseline-ecs-task-exec-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action    = "sts:AssumeRole"
#       Effect    = "Allow"
#       Principal = { Service = "ecs-tasks.amazonaws.com" }
#     }]
#   })
#
#   tags = local.baseline_tags
# }
#
# # 7.3. Attaching an AWS Managed Policy for Fargate Execution
# resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
#   role       = aws_iam_role.ecs_task_exec_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }
#
# # 7.4. Task definition (Nginx, 256 mCPU, 512 MiB RAM)
# resource "aws_ecs_task_definition" "baseline" {
#   family                   = "baseline-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn
#
#   container_definitions = jsonencode([{
#     name      = "nginx"
#     image     = "nginx:latest"
#     cpu       = 128
#     memory    = 256
#     essential = true
#     portMappings = [{
#       containerPort = 80
#       hostPort      = 80
#     }]
#   }])
#
#   tags = local.baseline_tags
# }
#
# # 7.5. We take the default VPC and Subnets
# data "aws_vpc" "default" {
#   default = true
# }
# data "aws_subnets" "default" {
#     filter {
#         name   = "vpc-id"
#         values = [data.aws_vpc.default.id]
#     }
# }
# data "aws_security_group" "default" {
#   name   = "default"
#   vpc_id = data.aws_vpc.default.id
# }
#
# # 7.6. Service: 1 task on Fargate
# resource "aws_ecs_service" "baseline" {
#   name            = "baseline-service"
#   cluster         = aws_ecs_cluster.baseline.id
#   task_definition = aws_ecs_task_definition.baseline.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#
#   network_configuration {
#     subnets         = data.aws_subnets.default.ids
#     security_groups = [data.aws_security_group.default.id]
#     assign_public_ip = false        # не публикуем в интернет
#   }
#
#   tags = local.baseline_tags
# }


###############################################################################
# 1. Terraform & Provider
###############################################################################
# terraform {
#   required_version = ">= 1.0"
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">= 5.50.0"
#     }
#   }
# }
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# second provider for CUR (us-east-1) for module finops_cur
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

###############################################################################
# 2. Общие переменные
###############################################################################
variable "project"     {
  default = "cost-baseline-trash"
}
variable "baseline_tags" {
  type    = map(string)
  default = { Purpose = "cost-baseline-trash" }
}

###############################################################################
# 3. Модули
###############################################################################
# module "compute" {
#   source        = "../../modules/baseline_compute"
#   baseline_tags = var.baseline_tags
# }
#
# module "rds" {
#   source        = "../../modules/baseline_rds"
#   baseline_tags = var.baseline_tags
# }
#
# module "ecs" {
#   source        = "../../modules/baseline_ecs"
#   baseline_tags = var.baseline_tags
# }

module "finops_cur" {                 # ← new block
  source      = "../../modules/finops_cur"
  project     = var.project
  aws_region  = "eu-central-1"
  providers = {
    aws         = aws                # main provider
    aws.us_east_1 = aws.us_east_1    # alias for CUR
    random        = random
  }
}
