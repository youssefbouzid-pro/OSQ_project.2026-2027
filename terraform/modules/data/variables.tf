variable "name_prefix" {
  type        = string
  description = "Prefix for table names, e.g. cloudybttounsi-dev."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-41 chars, lowercase alphanumeric and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every table."
  default     = {}
}
