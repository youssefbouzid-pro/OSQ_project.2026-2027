variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. osq-dev."
}

variable "vpc_id" {
  type        = string
  description = "VPC the lab security group is created in."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet the orchestrator launches labs into. Must have outbound internet so Tailscale can reach its coordination server."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default     = {}
}

variable "lab_ami_id" {
  type        = string
  description = "Optional AMI baked into the launch template. Leave null: the orchestrator resolves the per-family AMI from SSM at launch time and overrides it."
  default     = null
}

variable "launch_template_name" {
  type        = string
  description = "Name of the launch template the orchestrator targets."
  default     = ""
}

variable "tailscale_auth_key_parameter_name" {
  type        = string
  description = "SSM SecureString parameter the instance reads its Tailscale auth key from at boot. The value is never baked into an AMI or user-data."
  default     = "/cloudybt/tailscale/authkey"
}

variable "ami_ids" {
  type        = map(string)
  description = "Map of lab family to a baked AMI id, e.g. { linux = \"ami-0123...\" }. Empty until the AMIs exist; each entry creates its /cloudybt/ami/<family> parameter."
  default     = {}
}

variable "enable_ssm_access" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore so Session Manager stays available as the docs/14 fallback if Tailscale is unusable. Tailscale remains the primary access path."
  default     = true
}
