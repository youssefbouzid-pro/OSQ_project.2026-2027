output "trail_name" {
  description = "Name of the CloudTrail trail. Control GOV-001 in docs/10 asserts on this."
  value       = aws_cloudtrail.main.name
}

output "trail_arn" {
  description = "ARN of the CloudTrail trail."
  value       = aws_cloudtrail.main.arn
}

output "log_bucket_name" {
  description = "Private bucket holding the CloudTrail log objects."
  value       = aws_s3_bucket.trail.id
}

output "kms_key_arn" {
  description = "KMS key encrypting the trail and its log objects."
  value       = aws_kms_key.trail.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector id, or null when enable_guardduty is false."
  value       = try(aws_guardduty_detector.main[0].id, null)
}
