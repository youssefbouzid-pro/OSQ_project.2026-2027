# API Gateway HTTP API + the three Lambdas in docs/14/docs/15:
#
#   session_handler  the docs/16 HTTP API
#   orchestrator     launch and terminate ephemeral lab EC2
#   ttl_gc           scheduled reaper (docs/15)
#
# Lambdas are deliberately NOT attached to a VPC. The app subnets have no
# NAT and no VPC endpoints, so a VPC-attached function could not reach
# DynamoDB, EC2 or SSM. The functions run in the AWS service network and
# are reached only through their IAM roles.

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name = var.name_prefix

  account_id = data.aws_caller_identity.current.id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current

  log_retention_days = 365

  # docs/12 approved instance types, sorted. Kept as a local so the IAM
  # allow-list and the tests read from one place, and so a new type is a
  # single edit rather than a hunt through policy documents. Policy
  # LAB-002 carries the same list at plan time.
  approved_instance_types = ["t4g.medium", "t4g.micro", "t4g.small"]

  lambda_env = {
    USERS_TABLE                  = var.users_table_name
    LABS_TABLE                   = var.labs_table_name
    SESSIONS_TABLE               = var.sessions_table_name
    ACTIVITY_TABLE               = var.activity_table_name
    ORCHESTRATOR_FUNCTION        = "${local.name}-orchestrator"
    TERMINATOR_FUNCTION          = "${local.name}-orchestrator"
    AMI_PARAMETER_PREFIX         = var.ami_parameter_prefix
    LAB_LAUNCH_TEMPLATE          = var.launch_template_name
    LAB_SECURITY_GROUP_ID        = var.lab_security_group_id
    LAB_SUBNET_ID                = var.lab_subnet_id
    LAB_INSTANCE_PROFILE         = var.lab_instance_profile_name
    TAILSCALE_AUTH_KEY_PARAMETER = var.tailscale_auth_key_parameter_name
    TTL_MINUTES                  = tostring(var.ttl_minutes)
    READY_TIMEOUT_SECONDS        = tostring(var.ready_timeout_seconds)
    MAX_ACTIVE_LABS_PER_USER     = tostring(var.max_active_labs_per_user)
    MAX_ACTIVE_LABS_PLATFORM     = tostring(var.max_active_labs_platform)
  }

  table_arns = [
    var.users_table_arn,
    var.labs_table_arn,
    var.sessions_table_arn,
    var.activity_table_arn,
  ]

  # The nine documented routes (docs/16). Authorisation happens in the
  # session handler against the docs/16 matrix, so the gateway itself
  # carries no authorizer; NONE is stated explicitly rather than left
  # implicit.
  routes = toset([
    "GET /me",
    "GET /labs",
    "GET /labs/{labId}",
    "POST /labs/start",
    "GET /sessions",
    "GET /sessions/{sessionId}",
    "POST /sessions/{sessionId}/destroy",
    "POST /sessions/{sessionId}/flags",
    "GET /activity",
  ])

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Packaging
#
# One zip for all three functions: they share lambdas/common, and the whole
# backend is a few tens of kilobytes.
# ---------------------------------------------------------------------------

data "archive_file" "backend" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/backend.zip"

  excludes = [
    "**/__pycache__",
    "**/*.pyc",
    "**/*.pyo",
    "**/.pytest_cache",
    "**/.DS_Store",
  ]
}

# ---------------------------------------------------------------------------
# Encryption and dead-letter queue shared by every function
# ---------------------------------------------------------------------------

resource "aws_kms_key" "logs" {
  description             = "${local.name} Lambda logs and environment encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${local.name}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-lambda-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.logs.arn
  tags                      = local.tags
}

data "aws_iam_policy_document" "dlq" {
  statement {
    sid    = "AllowLambdaToEnqueueFailures"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.dlq.json
}

# ---------------------------------------------------------------------------
# IAM: shared DynamoDB access
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "dynamodb_read_write" {
  statement {
    sid    = "ReadWriteLabTables"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = concat(local.table_arns, [for arn in local.table_arns : "${arn}/index/*"])
  }
}

data "aws_iam_policy_document" "ec2_provision" {
  # RunInstances cannot be scoped to a concrete resource before the
  # instance exists, so the guardrail here is the instance-type condition.
  # Policy LAB-002 enforces the same list at plan time.
  statement {
    sid    = "RunApprovedLabInstances"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values   = local.approved_instance_types
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:Region"
      values   = [local.region]
    }
  }

  statement {
    sid    = "ManageLabInstances"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:CreateTags",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = [
      "arn:${local.partition.partition}:ec2:${local.region}:${local.account_id}:instance/*",
      "arn:${local.partition.partition}:ec2:${local.region}:${local.account_id}:volume/*",
      "arn:${local.partition.partition}:ec2:${local.region}:${local.account_id}:launch-template/*",
    ]
  }

  statement {
    sid    = "ReadApprovedAmis"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:${local.partition.partition}:ssm:${local.region}:${local.account_id}:parameter${var.ami_parameter_prefix}/*",
    ]
  }

  statement {
    sid    = "DecryptAmiParameters"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# session_handler
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "session_handler" {
  name              = "/aws/lambda/${local.name}-session-handler"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = local.tags
}

resource "aws_iam_role" "session_handler" {
  name = "${local.name}-session-handler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "session_handler" {
  name   = "session-handler"
  role   = aws_iam_role.session_handler.id
  policy = data.aws_iam_policy_document.dynamodb_read_write.json
}

data "aws_iam_policy_document" "session_handler_invoke" {
  statement {
    sid       = "InvokeOrchestrator"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.orchestrator.arn]
  }

  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.session_handler.arn}:*"]
  }

  statement {
    sid       = "SendFailuresToDlq"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
}

resource "aws_iam_role_policy" "session_handler_invoke" {
  name   = "invoke-orchestrator"
  role   = aws_iam_role.session_handler.id
  policy = data.aws_iam_policy_document.session_handler_invoke.json
}

resource "aws_lambda_function" "session_handler" {
  # checkov:skip=CKV_AWS_117: Not VPC-attached on purpose. The app
  # subnets have no NAT and no VPC endpoints, so a VPC-attached function
  # could not reach DynamoDB, EC2 or SSM. It runs in the AWS service
  # network behind its IAM role.
  # checkov:skip=CKV_AWS_272: Code signing needs a signing profile and a
  # release step. Out of scope for the PoC; revisit before any real
  # deployment.
  function_name    = "${local.name}-session-handler"
  description      = "osq HTTP API (docs/16)."
  role             = aws_iam_role.session_handler.arn
  handler          = "session_handler.handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 29
  memory_size      = 256

  # Cost guardrail: the platform is a PoC, not a service under load.
  reserved_concurrent_executions = 10

  kms_key_arn = aws_kms_key.logs.arn

  environment {
    variables = local.lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_cloudwatch_log_group.session_handler,
    aws_sqs_queue_policy.dlq,
  ]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# orchestrator
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${local.name}-orchestrator"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = local.tags
}

resource "aws_iam_role" "orchestrator" {
  name = "${local.name}-orchestrator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

data "aws_iam_policy_document" "orchestrator" {
  statement {
    sid    = "WriteSessionState"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      var.sessions_table_arn,
      "${var.sessions_table_arn}/index/*",
      var.labs_table_arn,
      var.activity_table_arn,
    ]
  }

  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.orchestrator.arn}:*"]
  }

  statement {
    sid       = "SendFailuresToDlq"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
}

resource "aws_iam_role_policy" "orchestrator" {
  name   = "orchestrator"
  role   = aws_iam_role.orchestrator.id
  policy = data.aws_iam_policy_document.orchestrator.json
}

resource "aws_iam_role_policy" "orchestrator_ec2" {
  name   = "provision-labs"
  role   = aws_iam_role.orchestrator.id
  policy = data.aws_iam_policy_document.ec2_provision.json
}

resource "aws_lambda_function" "orchestrator" {
  # checkov:skip=CKV_AWS_117: Not VPC-attached on purpose. The app
  # subnets have no NAT and no VPC endpoints, so a VPC-attached function
  # could not reach DynamoDB, EC2 or SSM. It runs in the AWS service
  # network behind its IAM role.
  # checkov:skip=CKV_AWS_272: Code signing needs a signing profile and a
  # release step. Out of scope for the PoC; revisit before any real
  # deployment.
  function_name    = "${local.name}-orchestrator"
  description      = "Launches and terminates ephemeral lab EC2 (docs/15)."
  role             = aws_iam_role.orchestrator.arn
  handler          = "orchestrator.handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 300
  memory_size      = 256

  reserved_concurrent_executions = 4

  kms_key_arn = aws_kms_key.logs.arn

  environment {
    variables = local.lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_cloudwatch_log_group.orchestrator,
    aws_sqs_queue_policy.dlq,
  ]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# ttl_gc
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ttl_gc" {
  name              = "/aws/lambda/${local.name}-ttl-gc"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = local.tags
}

resource "aws_iam_role" "ttl_gc" {
  name = "${local.name}-ttl-gc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

data "aws_iam_policy_document" "ttl_gc" {
  statement {
    sid    = "ReapSessions"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      var.sessions_table_arn,
      "${var.sessions_table_arn}/index/*",
      var.activity_table_arn,
    ]
  }

  statement {
    sid    = "TerminateExpiredLabs"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:TerminateInstances",
    ]
    resources = [
      "arn:${local.partition.partition}:ec2:${local.region}:${local.account_id}:instance/*",
      "arn:${local.partition.partition}:ec2:${local.region}:${local.account_id}:volume/*",
    ]
  }

  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.ttl_gc.arn}:*"]
  }

  statement {
    sid       = "SendFailuresToDlq"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
}

resource "aws_iam_role_policy" "ttl_gc" {
  name   = "ttl-gc"
  role   = aws_iam_role.ttl_gc.id
  policy = data.aws_iam_policy_document.ttl_gc.json
}

resource "aws_lambda_function" "ttl_gc" {
  # checkov:skip=CKV_AWS_117: Not VPC-attached on purpose. The app
  # subnets have no NAT and no VPC endpoints, so a VPC-attached function
  # could not reach DynamoDB, EC2 or SSM. It runs in the AWS service
  # network behind its IAM role.
  # checkov:skip=CKV_AWS_272: Code signing needs a signing profile and a
  # release step. Out of scope for the PoC; revisit before any real
  # deployment.
  function_name    = "${local.name}-ttl-gc"
  description      = "TTL garbage collector (docs/15)."
  role             = aws_iam_role.ttl_gc.arn
  handler          = "ttl_gc.handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 120
  memory_size      = 128

  reserved_concurrent_executions = 2

  kms_key_arn = aws_kms_key.logs.arn

  environment {
    variables = local.lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_cloudwatch_log_group.ttl_gc,
    aws_sqs_queue_policy.dlq,
  ]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# TTL schedule: every minute, per docs/15.
# ---------------------------------------------------------------------------

resource "aws_scheduler_schedule_group" "labs" {
  name = "${local.name}-labs"
  tags = local.tags
}

resource "aws_iam_role" "scheduler" {
  name = "${local.name}-ttl-gc-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-ttl-gc"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.ttl_gc.arn
    }]
  })
}

resource "aws_scheduler_schedule" "ttl_gc" {
  name       = "${local.name}-ttl-gc"
  group_name = aws_scheduler_schedule_group.labs.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(1 minute)"
  # Stated rather than left to the provider default: if this ever reads
  # DISABLED, every lab leaks past its TTL with no sweep to catch it.
  state       = "ENABLED"
  description = "Terminate labs whose TTL has passed (docs/15)."

  target {
    arn      = aws_lambda_function.ttl_gc.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "ttl-gc" })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }

  # Encrypt the schedule payload with the same CMK as the logs.
  kms_key_arn = aws_kms_key.logs.arn
}

# ---------------------------------------------------------------------------
# HTTP API (docs/16). Explicit routes so the Lambda sees a real routeKey.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-http"
  description   = "osq learner API (docs/16)."
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }

  tags = local.tags
}

resource "aws_apigatewayv2_integration" "session_handler" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.session_handler.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "routes" {
  # checkov:skip=CKV_AWS_309: Authorisation is personal access tokens
  # checked in the session handler against the docs/16 matrix. A gateway
  # JWT/IAM authorizer would require Cognito or OIDC, which docs/14 and
  # docs/16 explicitly keep out of the PoC.
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.http.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.session_handler.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name}-http"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = local.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.session_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
