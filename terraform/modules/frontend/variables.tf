variable "name_prefix" {
  type        = string
  description = "Prefix for the bucket and distribution aliases, e.g. cloudybttounsi-dev."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-41 chars, lowercase alphanumeric and hyphens."
  }
}

variable "source_dir" {
  type        = string
  description = "Absolute path to the static site to serve. Objects are uploaded by `make deploy-frontend`, not by Terraform."
}

variable "price_class" {
  type        = string
  description = "CloudFront edge price class. PriceClass_100 is the cheapest and covers the PoC audience."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default     = {}
}
