output "state_bucket" {
  description = "Terraform state S3 bucket."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "DynamoDB table used for state locking."
  value       = aws_dynamodb_table.lock.name
}

output "state_kms_key_arn" {
  description = "KMS key ARN used to encrypt state."
  value       = aws_kms_key.state.arn
}

output "alerts_topic_arn" {
  description = "SNS topic for budget, drift, and compliance alerts."
  value       = aws_sns_topic.alerts.arn
}

output "backend_hcl" {
  description = "Paste into terraform/environments/dev/backend.hcl."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.state.bucket}"
    key            = "dev/terraform.tfstate"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
    encrypt        = true
  EOT
}
