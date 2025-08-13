terraform {
  required_version = ">= 1.5"
  required_providers {
    aws      = {
      source = "hashicorp/aws",
      version = ">= 5.0"
    }
    # external = { source = "hashicorp/external", version = ">= 2.3" }
  }
}

data "archive_file" "scan_lambda_zip" {
  type       = "zip"
  source_dir = "${path.module}/lambda-node"
  output_path = "${path.module}/lambda-node.zip"
}

resource "aws_iam_role" "scan_lambda_role" {
  name = "cost-guard-scan-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scan_lambda_policy" {
  name = "cost-guard-scan-lambda-policy"
  role = aws_iam_role.scan_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ec2:DescribeInstances", "ec2:StopInstances", "ec2:DescribeVolumes", "ec2:ModifyVolumeAttribute"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["cloudwatch:GetMetricData", "cloudwatch:ListMetrics", "cloudwatch:GetMetricStatistics"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "scan" {
  function_name = "cost-guard-scan-node"
  filename      = data.archive_file.scan_lambda_zip.output_path
  handler       = "idle_scan.handler"      # `<file name>.<name of the exported function>`
  runtime       = "nodejs18.x"
  timeout       = var.lambda_timeout
  role          = aws_iam_role.scan_lambda_role.arn
  source_code_hash = filebase64sha256("${path.module}/lambda-node/idle_scan.mjs")
  environment {
    variables = {
      REGIONS             = join(",", var.regions)
      IDLE_THRESHOLD_DAYS = tostring(var.idle_threshold_days)
      EXCLUDE_TAGS        = join(",", var.exclude_tags)
      DRY_RUN             = tostring(var.dry_run)
    }
  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "cost-guard-schedule"
  schedule_expression = var.schedule_expression   # by default rate(1 hour)
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "scanLambda"
  arn       = aws_lambda_function.scan.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scan.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
