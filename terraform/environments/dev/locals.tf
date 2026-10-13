locals {
  name_prefix = "${var.project}-${var.environment}"

  # Applied by every module. The account and owner are deliberately
  # absent: they belong in the provider-level default_tags, which the
  # bootstrap stack sets up for the shared account.
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "cloudybt-tounsi"
  }
}
