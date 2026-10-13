# Offline tests for the api module.
#
# `terraform validate` proves the configuration is well-formed, tflint
# proves it follows AWS conventions, and Checkov proves its security
# posture. None of those prove the module is *wired correctly*: that the
# environment variables name the tables the data module creates, that
# every docs/16 route exists, that the instance-type allow-list still
# matches docs/12. Those bugs only surface on the first apply, where they
# cost an afternoon, so they are what these tests pin down.
#
# The AWS provider is mocked, so this runs with no credentials and is
# safe to put in CI. Only config-derived values are asserted on: anything
# that flows from a mocked data source (account id, region, policy JSON,
# resource ARNs) is a placeholder here and would be meaningless to check.

mock_provider "aws" {
  # aws_iam_policy_document is computed by the provider, so mocking the
  # provider replaces its JSON with a placeholder that no longer parses.
  # The resources that consume those documents then fail to plan and take
  # every run down with them. Pin the shape to a valid empty policy: the
  # statements themselves are not what these tests assert on (the
  # instance-type allow-list is asserted through local.approved_instance_types,
  # which is the value the policy document actually reads).
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "osq-test"

  lambda_source_dir = "../../../lambdas"

  users_table_name    = "osq-test-users"
  users_table_arn     = "arn:aws:dynamodb:us-east-1:111111111111:table/osq-test-users"
  labs_table_name     = "osq-test-labs"
  labs_table_arn      = "arn:aws:dynamodb:us-east-1:111111111111:table/osq-test-labs"
  sessions_table_name = "osq-test-sessions"
  sessions_table_arn  = "arn:aws:dynamodb:us-east-1:111111111111:table/osq-test-sessions"
  activity_table_name = "osq-test-activity"
  activity_table_arn  = "arn:aws:dynamodb:us-east-1:111111111111:table/osq-test-activity"

  lab_subnet_id             = "subnet-0aaa1111"
  lab_security_group_id     = "sg-0aaa1111"
  lab_instance_profile_name = "osq-test-lab"
  launch_template_name      = "osq-test-lab"

  ttl_minutes              = 60
  max_active_labs_per_user = 4
  max_active_labs_platform = 4
  ready_timeout_seconds    = 180

  tags = {
    Project   = "osq"
    Component = "osq"
  }
}

# ---------------------------------------------------------------------------
# docs/16: the HTTP API surface
# ---------------------------------------------------------------------------

run "every_docs16_route_exists" {
  command = plan

  assert {
    condition = sort([
      "GET /me",
      "GET /labs",
      "GET /labs/{labId}",
      "POST /labs/start",
      "GET /sessions",
      "GET /sessions/{sessionId}",
      "POST /sessions/{sessionId}/destroy",
      "POST /sessions/{sessionId}/flags",
      "GET /activity",
    ]) == sort([for k, _ in local.routes : k])
    error_message = "local.routes must list the nine endpoints in docs/16, exactly and no more."
  }

  assert {
    condition     = length(local.routes) == 9
    error_message = "docs/16 documents nine endpoints; a tenth means the route table and the doc have diverged."
  }
}

run "authorization_lives_in_the_handler" {
  command = plan

  assert {
    condition = alltrue([
      for route in aws_apigatewayv2_route.routes :
      route.authorization_type == "NONE"
    ])
    error_message = "docs/16 authorises personal access tokens in the handler, not at the gateway. Every route must be authorization_type NONE; a JWT or IAM authorizer would need Cognito, which docs/14 keeps out of the PoC."
  }
}

# ---------------------------------------------------------------------------
# docs/12: the instance-type allow-list
# ---------------------------------------------------------------------------

run "approved_types_match_docs12" {
  command = plan

  assert {
    condition     = local.approved_instance_types == ["t4g.medium", "t4g.micro", "t4g.small"]
    error_message = "local.approved_instance_types must equal the docs/12 list. This local is the single source for the ec2:InstanceType condition, so it is the thing LAB-002 and the IAM boundary are meant to agree on."
  }
}

run "no_reserved_generations_in_the_allow_list" {
  command = plan

  assert {
    condition = alltrue([
      for t in local.approved_instance_types :
      can(regex("^t4g\\.(micro|small|medium)$", t))
    ])
    error_message = "only t4g.micro, t4g.small and t4g.medium are approved. t3 and t2 are x86 and, per docs/12, not part of the cost model."
  }
}

# ---------------------------------------------------------------------------
# Lambda wiring: the env block is where a hard-coded table name hides
# ---------------------------------------------------------------------------

run "lambdas_receive_the_injected_tables" {
  command = plan

  assert {
    condition = [
      aws_lambda_function.session_handler.environment[0].variables["USERS_TABLE"],
      aws_lambda_function.session_handler.environment[0].variables["LABS_TABLE"],
      aws_lambda_function.session_handler.environment[0].variables["SESSIONS_TABLE"],
      aws_lambda_function.session_handler.environment[0].variables["ACTIVITY_TABLE"],
      ] == [
      var.users_table_name,
      var.labs_table_name,
      var.sessions_table_name,
      var.activity_table_name,
    ]
    error_message = "the session handler must read its table names from the injected variables. A mismatch here is a hard-coded name that only fails at runtime."
  }

  assert {
    condition = (
      aws_lambda_function.session_handler.environment[0].variables["LAB_SUBNET_ID"] == var.lab_subnet_id &&
      aws_lambda_function.session_handler.environment[0].variables["LAB_SECURITY_GROUP_ID"] == var.lab_security_group_id &&
      aws_lambda_function.session_handler.environment[0].variables["LAB_LAUNCH_TEMPLATE"] == var.launch_template_name &&
      aws_lambda_function.session_handler.environment[0].variables["LAB_INSTANCE_PROFILE"] == var.lab_instance_profile_name
    )
    error_message = "the lab wiring (subnet, security group, launch template, instance profile) must flow from the lab module, not be spelled out here."
  }

  assert {
    condition = (
      aws_lambda_function.session_handler.environment[0].variables["TTL_MINUTES"] == "60" &&
      aws_lambda_function.session_handler.environment[0].variables["READY_TIMEOUT_SECONDS"] == "180" &&
      aws_lambda_function.session_handler.environment[0].variables["MAX_ACTIVE_LABS_PER_USER"] == "4" &&
      aws_lambda_function.session_handler.environment[0].variables["MAX_ACTIVE_LABS_PLATFORM"] == "4"
    )
    error_message = "docs/12 parameter values (60 minute TTL, 180 second ready timeout, quota of 4) must reach the functions as strings."
  }
}

run "three_functions_share_one_archive" {
  command = plan

  assert {
    condition = length(distinct([
      aws_lambda_function.session_handler.filename,
      aws_lambda_function.orchestrator.filename,
      aws_lambda_function.ttl_gc.filename,
    ])) == 1
    error_message = "all three functions must share one zip: they share lambdas/common, and separate zips would let them drift apart."
  }

  assert {
    condition     = aws_lambda_function.session_handler.handler == "session_handler.handler.lambda_handler"
    error_message = "the session handler entry point must be session_handler.handler.lambda_handler."
  }

  assert {
    condition     = aws_lambda_function.orchestrator.handler == "orchestrator.handler.lambda_handler"
    error_message = "the orchestrator entry point must be orchestrator.handler.lambda_handler."
  }

  assert {
    condition     = aws_lambda_function.ttl_gc.handler == "ttl_gc.handler.lambda_handler"
    error_message = "the TTL GC entry point must be ttl_gc.handler.lambda_handler, not gc.handler, which would shadow the stdlib module."
  }
}

run "lambdas_are_hardened" {
  command = plan

  assert {
    condition = alltrue([
      for fn in [
        aws_lambda_function.session_handler,
        aws_lambda_function.orchestrator,
        aws_lambda_function.ttl_gc,
      ] :
      length(fn.tracing_config) == 1 && fn.tracing_config[0].mode == "Active"
    ])
    error_message = "X-Ray active tracing must be on for every function."
  }

  assert {
    condition = alltrue([
      for fn in [
        aws_lambda_function.session_handler,
        aws_lambda_function.orchestrator,
        aws_lambda_function.ttl_gc,
      ] :
      length(fn.dead_letter_config) == 1
    ])
    error_message = "every function needs a dead-letter queue so a failing invoke is retried and visible rather than dropped."
  }

  assert {
    condition = alltrue([
      for fn in [
        aws_lambda_function.session_handler,
        aws_lambda_function.orchestrator,
        aws_lambda_function.ttl_gc,
      ] :
      length(fn.vpc_config) == 0
    ])
    error_message = "the Lambdas must stay outside the VPC. The app subnets have no NAT and no VPC endpoints, so a VPC-attached function could not reach DynamoDB, EC2 or SSM. This is deliberate; changing it means adding egress first."
  }
}

# ---------------------------------------------------------------------------
# docs/04: TTL is a per-minute sweep
# ---------------------------------------------------------------------------

run "ttl_gc_runs_every_minute" {
  command = plan

  assert {
    condition     = aws_scheduler_schedule.ttl_gc.schedule_expression == "rate(1 minute)"
    error_message = "docs/04 requires the TTL sweep to run every minute."
  }

  assert {
    condition     = aws_scheduler_schedule.ttl_gc.state == "ENABLED"
    error_message = "the TTL schedule must be enabled; a disabled sweep would leak every lab past its expiry."
  }
}

# ---------------------------------------------------------------------------
# docs/09: log retention
# ---------------------------------------------------------------------------

run "logs_are_retained_for_a_year" {
  command = plan

  assert {
    condition = alltrue([
      for group in [
        aws_cloudwatch_log_group.session_handler,
        aws_cloudwatch_log_group.orchestrator,
        aws_cloudwatch_log_group.ttl_gc,
        aws_cloudwatch_log_group.api_access,
      ] :
      group.retention_in_days == 365
    ])
    error_message = "every log group must retain 365 days, matching the audit retention in docs/09. Never leave retention unset: that keeps logs forever at full price."
  }
}
