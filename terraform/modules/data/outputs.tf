output "users_table_name" {
  description = "Name of the users table."
  value       = aws_dynamodb_table.users.name
}

output "users_table_arn" {
  description = "ARN of the users table."
  value       = aws_dynamodb_table.users.arn
}

output "labs_table_name" {
  description = "Name of the labs table."
  value       = aws_dynamodb_table.labs.name
}

output "labs_table_arn" {
  description = "ARN of the labs table."
  value       = aws_dynamodb_table.labs.arn
}

output "sessions_table_name" {
  description = "Name of the sessions table."
  value       = aws_dynamodb_table.sessions.name
}

output "sessions_table_arn" {
  description = "ARN of the sessions table."
  value       = aws_dynamodb_table.sessions.arn
}

output "activity_table_name" {
  description = "Name of the activity table."
  value       = aws_dynamodb_table.activity.name
}

output "activity_table_arn" {
  description = "ARN of the activity table."
  value       = aws_dynamodb_table.activity.arn
}
