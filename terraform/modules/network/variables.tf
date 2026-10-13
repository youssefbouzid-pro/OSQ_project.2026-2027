variable "project" {
  type        = string
  description = "Project name used for resource naming and tags."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project))
    error_message = "project must be 3-31 chars, lowercase alphanumeric and hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && startswith(var.vpc_cidr, "10.")
    error_message = "vpc_cidr must be a valid CIDR inside the 10.0.0.0/8 private range."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs (one per AZ). Public subnets carry labs, API edge and the ops host."
  default     = ["10.0.0.0/20", "10.0.16.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnets are required for AZ redundancy."
  }

  validation {
    condition = alltrue([
      for cidr in var.public_subnet_cidrs : cidrhost(cidr, 0) == split("/", cidr)[0]
    ])
    error_message = "every subnet CIDR must be the network address for its prefix. A /20 inside 10.0.0.0/16 starts at 0, 16, 32 or 48; 10.0.8.0/20 has host bits set and AWS rejects it."
  }
}

variable "app_subnet_cidrs" {
  type        = list(string)
  description = "Private application subnet CIDRs (backend only, no internet egress route)."
  default     = ["10.0.32.0/20", "10.0.48.0/20"]

  validation {
    condition     = length(var.app_subnet_cidrs) >= 1
    error_message = "At least one app subnet is required."
  }

  validation {
    condition = alltrue([
      for cidr in var.app_subnet_cidrs : cidrhost(cidr, 0) == split("/", cidr)[0]
    ])
    error_message = "every subnet CIDR must be the network address for its prefix. A /20 inside 10.0.0.0/16 starts at 0, 16, 32 or 48; 10.0.8.0/20 has host bits set and AWS rejects it."
  }
}

variable "data_subnet_cidrs" {
  type        = list(string)
  description = "Isolated data subnet CIDRs for a future data tier (no routes to IGW or NAT)."
  default     = ["10.0.64.0/20", "10.0.80.0/20"]

  validation {
    condition     = length(var.data_subnet_cidrs) >= 2
    error_message = "At least two data subnets are required for a DB subnet group."
  }

  validation {
    condition = alltrue([
      for cidr in var.data_subnet_cidrs : cidrhost(cidr, 0) == split("/", cidr)[0]
    ])
    error_message = "every subnet CIDR must be the network address for its prefix. A /20 inside 10.0.0.0/16 starts at 0, 16, 32 or 48; 10.0.8.0/20 has host bits set and AWS rejects it."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged into every resource."
  default     = {}
}
