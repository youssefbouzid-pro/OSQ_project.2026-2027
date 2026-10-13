output "launch_template_id" {
  description = "ID of the lab launch template."
  value       = aws_launch_template.lab.id
}

output "launch_template_name" {
  description = "Name of the lab launch template, as the orchestrator expects it."
  value       = aws_launch_template.lab.name
}

output "security_group_id" {
  description = "Security group attached to lab instances. Egress only."
  value       = aws_security_group.lab.id
}

output "subnet_id" {
  description = "Subnet labs are launched into."
  value       = var.subnet_id
}

output "instance_profile_name" {
  description = "Instance profile attached to lab instances."
  value       = aws_iam_instance_profile.lab.name
}

output "instance_role_name" {
  description = "IAM role assumed by lab instances."
  value       = aws_iam_role.lab_instance.name
}

output "tailscale_auth_key_parameter_name" {
  description = "SSM parameter instances read their Tailscale auth key from."
  value       = var.tailscale_auth_key_parameter_name
}

output "ami_parameter_names" {
  description = "SSM parameters holding the approved AMI id per lab family."
  value       = { for k, _ in var.ami_ids : k => "${local.ami_parameter_prefix}/${k}" }
}
