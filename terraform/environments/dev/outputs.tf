output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets for labs and edge services."
  value       = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  description = "Private app subnets for the backend."
  value       = module.network.app_subnet_ids
}

output "data_subnet_ids" {
  description = "Isolated data subnets reserved for a future data tier."
  value       = module.network.data_subnet_ids
}

output "api_endpoint" {
  description = "Base URL of the learner HTTP API. Seed the frontend with this."
  value       = module.api.api_endpoint
}

output "users_table_name" {
  description = "DynamoDB table holding users and token hashes."
  value       = module.data.users_table_name
}

output "labs_table_name" {
  description = "DynamoDB table holding the lab catalog and flags."
  value       = module.data.labs_table_name
}

output "sessions_table_name" {
  description = "DynamoDB table holding lab sessions."
  value       = module.data.sessions_table_name
}

output "activity_table_name" {
  description = "DynamoDB table holding the audit trail."
  value       = module.data.activity_table_name
}

output "launch_template_name" {
  description = "Launch template the orchestrator targets."
  value       = module.lab.launch_template_name
}

output "orchestrator_function_name" {
  description = "Lambda that launches and terminates labs."
  value       = module.api.orchestrator_function_name
}

output "ttl_gc_function_name" {
  description = "Lambda that reaps expired labs every minute."
  value       = module.api.ttl_gc_function_name
}

output "frontend_bucket_name" {
  description = "Private bucket holding the static web UI. Upload with `make deploy-frontend`."
  value       = module.frontend.bucket_name
}

output "frontend_distribution_id" {
  description = "CloudFront distribution to invalidate after each deploy."
  value       = module.frontend.distribution_id
}

output "frontend_url" {
  description = "Public HTTPS URL of the learner web UI."
  value       = module.frontend.url
}

output "trail_name" {
  description = "CloudTrail trail carrying the API activity audit (docs/10 control GOV-001)."
  value       = module.governance.trail_name
}

output "audit_log_bucket_name" {
  description = "Private bucket holding the CloudTrail log objects."
  value       = module.governance.log_bucket_name
}

output "guardduty_detector_id" {
  description = "GuardDuty detector monitoring the account."
  value       = module.governance.guardduty_detector_id
}

output "seed_users_command" {
  description = "Command that mints learner tokens. Tokens are printed once and never stored."
  value       = "make seed-users USERS_TABLE=${module.data.users_table_name}"
}

output "seed_labs_command" {
  description = "Command that loads the lab catalog, including the flags the API redacts."
  value       = "make seed-labs LABS_TABLE=${module.data.labs_table_name}"
}
