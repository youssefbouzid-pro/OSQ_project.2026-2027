output "bucket_name" {
  description = "Bucket holding the static site. Use with `make deploy-frontend`."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "CloudFront distribution id, used to invalidate the cache after a deploy."
  value       = aws_cloudfront_distribution.site.id
}

output "domain_name" {
  description = "Public URL of the web UI, e.g. d111111abcdef8.cloudfront.net."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "url" {
  description = "HTTPS URL of the web UI."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}
