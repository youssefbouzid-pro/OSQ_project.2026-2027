variable "project" {
  type        = string
  description = "Lowercase project name used for resource naming."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project))
    error_message = "project must be 3-31 chars, lowercase alphanumeric and hyphens, starting with a letter."
  }
}

variable "region" {
  type        = string
  description = "AWS region for the state backend and budget."
  default     = "us-east-1"
}

variable "budget_amount" {
  type        = string
  description = "Monthly account budget in USD. Set to empty to skip budget creation."
  default     = "20"
}

variable "alert_emails" {
  type        = list(string)
  description = "Email addresses subscribed to budget and drift alerts (confirm the SNS subscription after apply)."
  default     = []

  validation {
    condition     = length(var.alert_emails) <= 5
    error_message = "A budget notification supports at most 5 subscriber emails."
  }
}
