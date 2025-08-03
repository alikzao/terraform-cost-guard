output "lambda_arn" {
  description = "ARN name Lambda function for scanning idle resources"
  value       = aws_lambda_function.scan.arn
}

output "event_rule_arn" {
  description = "ARN rules EventBridge"
  value       = aws_cloudwatch_event_rule.schedule.arn
}
