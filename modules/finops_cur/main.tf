##############################
# FinOps PoC – CUR + Athena #
##############################
#
# Terraform ≥1.6, AWS provider ≥5.40
#
# ▸ Creates an S3 bucket (with force_destroy for quick cleanup)
# ▸ Enables Cost & Usage Report (daily, Parquet) with Athena integration
# ▸ Sets up an Athena workgroup + named query for daily cost
#
# NOTE: the CUR API is global and **must** be called in us‑east‑1.
#       Therefore we use a second provider alias (aws.us_east_1).
##############################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50.0"
      configuration_aliases = [ aws.us_east_1 ]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

data "aws_caller_identity" "current" {}
##############################
# Variables
##############################
variable "project" {
  description = "Short project name, used as prefix in resource names"
  type        = string
  default     = "finops-poc"
}

variable "aws_region" {
  description = "Main region for the PoC (e.g. eu-central-1)"
  type        = string
  default     = "eu-central-1"
}

variable "retention_days" {
  description = "How long (in days) to keep CUR objects before S3 auto‑deletes them"
  type        = number
  default     = 7
}

##############################
# Random suffix for unique bucket names
##############################
resource "random_id" "bucket" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project}-cur-${random_id.bucket.hex}"
}

##############################
# S3 bucket to receive CUR(Cost & Usage Report) files
##############################
resource "aws_s3_bucket" "cur" {
  provider = aws.us_east_1        # bucket can live anywhere; keep same provider for simplicity
  bucket   = local.bucket_name
  force_destroy = true            # easy cleanup after demo
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  provider = aws.us_east_1
  bucket = aws_s3_bucket.cur.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Новый ресурс для lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "cur_lifecycle" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.cur.id

  rule {
    id      = "expire-after-${var.retention_days}-days"
    status  = "Enabled"
    filter {
      prefix = "" # применяем ко всем объектам
    }
    expiration {
      days = var.retention_days
    }
  }
}
# Athena results bucket in the same region as CUR (eu-central-1)
resource "aws_s3_bucket" "athena_results" {
  bucket        = "athena-results-${data.aws_caller_identity.current.account_id}-eu-central-1"
  force_destroy = true
}

########################################
# Bucket policy — разрешаем CUR писать
########################################
data "aws_iam_policy_document" "cur_bucket" {
  statement {
    sid = "AWSBillingReportsGetAcl"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cur.arn]
  }

  statement {
    sid = "AWSBillingReportsPutObject"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cur.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "cur" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.cur.id
  policy   = data.aws_iam_policy_document.cur_bucket.json
}

# Block all forms of public access as an extra safety guard
resource "aws_s3_bucket_public_access_block" "cur" {
  provider                = aws.us_east_1
  bucket                  = aws_s3_bucket.cur.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##############################
# Cost & Usage Report (CUR) – daily, Parquet, Athena‑ready
##############################
resource "aws_cur_report_definition" "daily_parquet" {
  provider = aws.us_east_1

  report_name                = "${var.project}_daily_parquet"
  # time_unit                  = "DAILY"
  time_unit                  = "HOURLY"          # ← обязательно
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]

  s3_bucket = aws_s3_bucket.cur.id
  s3_region = aws_s3_bucket.cur.region
  s3_prefix = "cur/"            # folder inside the bucket

  additional_artifacts   = ["ATHENA"]  # auto‑generate Glue + Athena template
  refresh_closed_reports = true
  report_versioning      = "OVERWRITE_REPORT"
}

##############################
# Athena workgroup (optional but cleaner than "primary")
##############################
resource "aws_athena_workgroup" "finops" {
  name          = "finops-cur"
  state         = "ENABLED"
  description   = "Workgroup used for FinOps PoC queries on CUR"
  force_destroy = true

  # configuration {
  #   result_configuration {
  #     output_location = "s3://${aws_s3_bucket.cur.bucket}/athena-results/"
  #   }
  # }
  configuration {
    result_configuration {
      # бакет теперь в eu-central-1, тот же регион что и Athena
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
  }
}

##############################
# Example named query: daily total cost (USD)
##############################
resource "aws_athena_named_query" "daily_cost_usd" {
  name      = "daily_cost_usd"
  workgroup = aws_athena_workgroup.finops.id
  database  = "aws_cur"  # Glue DB created automatically by CUR+Athena integration
  query     = <<EOQ
SELECT
  bill_billing_period_start_date AS day,
  ROUND(SUM(line_item_unblended_cost), 2) AS cost_usd
FROM "${aws_cur_report_definition.daily_parquet.report_name}"
WHERE bill_billing_period_start_date >= date '2025-07-20'
GROUP BY 1
ORDER BY 1;
EOQ
}

##############################
# Outputs
##############################
output "bucket_name" {
  description = "Name of the S3 bucket storing CUR Parquet files"
  value       = aws_s3_bucket.cur.bucket
}

output "athena_workgroup" {
  description = "Name of the Athena workgroup created/used for cost queries"
  value       = aws_athena_workgroup.finops.name
}

##############################
# База в Glue, где появится таблица CUR
##############################

resource "aws_glue_catalog_database" "aws_cur" {
  name = "aws_cur"
}

##############################
# Crawler, который пройдёт по S3 и создаст таблицу
##############################
resource "aws_glue_crawler" "cur" {
  name         = "${var.project}-cur-crawler"
  role         = aws_iam_role.glue.arn
  database_name = aws_glue_catalog_database.aws_cur.name

  s3_target {
    path = "s3://${aws_s3_bucket.cur.bucket}/cur/"
  }

  configuration = jsonencode({
    Version = 1.0,
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

# Роль для Glue
resource "aws_iam_role" "glue" {
  name = "${var.project}-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "glue.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "glue" {
  name = "${var.project}-glue-policy"
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:ListBucket"], Resource = [
        aws_s3_bucket.cur.arn,
        "${aws_s3_bucket.cur.arn}/*",
        aws_s3_bucket.athena_results.arn,
        "${aws_s3_bucket.athena_results.arn}/*"
      ]},
      { Effect = "Allow", Action = ["glue:*"], Resource = "*" }
    ]
  })
}
