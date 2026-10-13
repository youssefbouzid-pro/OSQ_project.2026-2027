output "api_endpoint" {
  description = "Base URL of the learner HTTP API."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "api_id" {
  description = "ID of the HTTP API."
  value       = aws_apigatewayv2_api.http.id
}

output "session_handler_function_name" {
  description = "Name of the session handler Lambda."
  value       = aws_lambda_function.session_handler.function_name
}

output "session_handler_function_arn" {
  description = "ARN of the session handler Lambda."
  value       = aws_lambda_function.session_handler.arn
}

output "orchestrator_function_name" {
  description = "Name of the lab orchestrator Lambda."
  value       = aws_lambda_function.orchestrator.function_name
}

output "ttl_gc_function_name" {
  description = "Name of the TTL garbage collector Lambda."
  value       = aws_lambda_function.ttl_gc.function_name
}

output "lambda_package_sha" {
  description = "Hash of the shared Lambda package, useful for confirming a deploy picked up new code."
  value       = data.archive_file.backend.output_base64sha256
}
