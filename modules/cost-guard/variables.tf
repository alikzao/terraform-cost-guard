variable "regions" {
  description = "AWS regions to inspect (e.g. [\"eu-central-1\", \"us-east-1\"])."
  type        = list(string)
}

variable "idle_threshold_days" {
  description = "Number of consecutive days with 0‑usage metrics before a resource is considered idle."
  type        = number
  default     = 30
}

variable "exclude_tags" {
  description = "Tag keys that, when present on a resource, exclude it from action."
  type        = list(string)
  default     = []
}

variable "dry_run" {
  description = "When true (default) the module only simulates the stop / modify‑volume calls."
  type        = bool
  default     = true
}

variable "profile" {
  description = "Optional AWS CLI/SDK profile name to use for all commands."
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "Cron or rate expression for EventBridge (e.g. \"rate(1 hour)\")."
  type        = string
  default     = "rate(1 hour)"
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function (e.g. \"nodejs18.x\" or \"python3.9\")."
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_timeout" {
  description = "Timeout in seconds for the Lambda function."
  type        = number
  default     = 300
}
