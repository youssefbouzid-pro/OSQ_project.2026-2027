variable "region" {
  type        = string
  description = "AWS region for the dev environment."
  default     = "us-east-1"
}

variable "project" {
  type        = string
  description = "Project name used for resource naming and tags."
  default     = "osq"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project))
    error_message = "project must be 3-31 chars, lowercase alphanumeric and hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment for this directory."
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "ami_ids" {
  type        = map(string)
  description = "Lab family to baked AMI id. Leave empty until the AMIs exist; each entry creates its /cloudybt/ami/<family> SSM parameter."
  default     = {}

  validation {
    condition = alltrue([
      for family, _ in var.ami_ids :
      contains(["linux", "dba", "devops"], family)
    ])
    error_message = "ami_ids keys must be lab families: linux, dba or devops."
  }
}

variable "ttl_minutes" {
  type        = number
  description = "Default lab lifetime in minutes."
  default     = 60

  validation {
    condition     = var.ttl_minutes > 0 && var.ttl_minutes <= 60
    error_message = "docs/12 caps the TTL at 60 minutes."
  }
}

variable "max_active_labs_per_user" {
  type        = number
  description = "Concurrent lab quota per learner (docs/12)."
  default     = 4
}

variable "max_active_labs_platform" {
  type        = number
  description = "Concurrent labs across the whole platform (docs/12)."
  default     = 4
}

variable "ready_timeout_seconds" {
  type        = number
  description = "How long the orchestrator waits for EC2 status checks before failing a session."
  default     = 180
}
