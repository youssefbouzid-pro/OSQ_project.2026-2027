variable "name_prefix" {
  type        = string
  description = "Prefix for the trail, bucket and detector, e.g. osq-dev."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-41 chars, lowercase alphanumeric and hyphens."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days to keep CloudTrail log objects. docs/09 sets the audit retention bar."
  default     = 365

  validation {
    condition     = var.log_retention_days >= 90
    error_message = "audit retention must be at least 90 days; docs/09 treats the trail as part of the audit trail."
  }
}

variable "enable_guardduty" {
  type        = bool
  description = "Enable a GuardDuty detector. Off by default so a PoC account can opt in."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default     = {}
}
