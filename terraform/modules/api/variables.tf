variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. cloudybttounsi-dev."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default     = {}
}

variable "lambda_source_dir" {
  type        = string
  description = "Absolute path to the lambdas/ directory. All three functions share one zip because they share the common package."
}

# -- data tier ------------------------------------------------------------

variable "users_table_name" {
  type = string
}

variable "users_table_arn" {
  type = string
}

variable "labs_table_name" {
  type = string
}

variable "labs_table_arn" {
  type = string
}

variable "sessions_table_name" {
  type = string
}

variable "sessions_table_arn" {
  type = string
}

variable "activity_table_name" {
  type = string
}

variable "activity_table_arn" {
  type = string
}

# -- lab tier -------------------------------------------------------------

variable "lab_subnet_id" {
  type        = string
  description = "Public subnet the orchestrator launches labs into."
}

variable "lab_security_group_id" {
  type = string
}

variable "lab_instance_profile_name" {
  type = string
}

variable "launch_template_name" {
  type = string
}

variable "tailscale_auth_key_parameter_name" {
  type    = string
  default = "/cloudybt/tailscale/authkey"
}

variable "ami_parameter_prefix" {
  type    = string
  default = "/cloudybt/ami"
}

# -- tuning ---------------------------------------------------------------

variable "ttl_minutes" {
  type        = number
  description = "Default lab lifetime. docs/12 caps this at 60."
  default     = 60
}

variable "max_active_labs_per_user" {
  type    = number
  default = 4
}

variable "max_active_labs_platform" {
  type    = number
  default = 4
}

variable "ready_timeout_seconds" {
  type        = number
  description = "How long the orchestrator waits for EC2 status checks before failing the session."
  default     = 180
}
