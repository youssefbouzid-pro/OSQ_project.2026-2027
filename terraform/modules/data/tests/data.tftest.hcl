# Offline tests for the data module.
#
# The DynamoDB shape in docs/16 is the contract the whole backend is
# written against: a token resolves through the by-token-hash index, a
# learner's sessions list comes back most-recent-first through by-user,
# and the sessions table carries no TTL because terminated sessions are
# the audit trail. None of that is visible from `terraform validate`, and
# all of it is cheap to get wrong.

mock_provider "aws" {}

variables {
  name_prefix = "osq-test"
  tags        = { Project = "osq" }
}

run "all_four_tables_exist" {
  command = plan

  assert {
    condition = (
      {
        users    = aws_dynamodb_table.users.name
        labs     = aws_dynamodb_table.labs.name
        sessions = aws_dynamodb_table.sessions.name
        activity = aws_dynamodb_table.activity.name
        } == {
        users    = "osq-test-users"
        labs     = "osq-test-labs"
        sessions = "osq-test-sessions"
        activity = "osq-test-activity"
      }
    )
    error_message = "docs/16 names four tables; each must be <name_prefix>-<table> so they cannot collide across environments."
  }
}

run "primary_keys_match_docs16" {
  command = plan

  assert {
    condition = (
      aws_dynamodb_table.users.hash_key == "userId" &&
      aws_dynamodb_table.labs.hash_key == "labId" &&
      aws_dynamodb_table.sessions.hash_key == "sessionId" &&
      aws_dynamodb_table.activity.hash_key == "eventId"
    )
    error_message = "each table's hash key must be the one docs/16 specifies."
  }
}

run "users_carry_the_token_hash_index" {
  command = plan

  assert {
    condition = anytrue([
      for gsi in aws_dynamodb_table.users.global_secondary_index :
      gsi.name == "by-token-hash" && gsi.hash_key == "tokenHash"
    ])
    error_message = "without by-token-hash every request would resolve a token with a table scan."
  }
}

run "sessions_carry_the_user_index" {
  command = plan

  assert {
    condition = anytrue([
      for gsi in aws_dynamodb_table.sessions.global_secondary_index :
      gsi.name == "by-user" && gsi.hash_key == "userId" && gsi.range_key == "createdAt"
    ])
    error_message = "docs/16 requires by-user (userId, createdAt) so a learner's session list is most-recent-first without a scan."
  }
}

run "sessions_have_no_ttl" {
  command = plan

  # Deliberate, and asserted so it cannot be flipped casually. DynamoDB
  # TTL would silently delete terminated sessions, which are the audit
  # trail (docs/04, docs/16). Retention is a process concern.
  assert {
    condition     = length(aws_dynamodb_table.sessions.ttl) == 0
    error_message = "the sessions table must not enable DynamoDB TTL; terminated sessions are the audit trail and must survive."
  }

  assert {
    condition     = length(aws_dynamodb_table.activity.ttl) == 0
    error_message = "the activity table must not enable DynamoDB TTL either; audit events are append-only and retained per docs/09."
  }
}

run "tables_are_on_demand_and_recoverable" {
  command = plan

  assert {
    condition = alltrue([
      for table in [
        aws_dynamodb_table.users,
        aws_dynamodb_table.labs,
        aws_dynamodb_table.sessions,
        aws_dynamodb_table.activity,
      ] :
      table.billing_mode == "PAY_PER_REQUEST"
    ])
    error_message = "docs/14 calls for on-demand billing: the PoC is free-tier friendly and traffic is bursty, so provisioned capacity would be paid for and unused."
  }

  assert {
    condition = alltrue([
      for table in [
        aws_dynamodb_table.users,
        aws_dynamodb_table.labs,
        aws_dynamodb_table.sessions,
        aws_dynamodb_table.activity,
      ] :
      table.point_in_time_recovery[0].enabled == true
    ])
    error_message = "point-in-time recovery must be on for every table; sessions and activity are the audit trail."
  }

  assert {
    condition = alltrue([
      for table in [
        aws_dynamodb_table.users,
        aws_dynamodb_table.labs,
        aws_dynamodb_table.sessions,
        aws_dynamodb_table.activity,
      ] :
      table.server_side_encryption[0].enabled == true
    ])
    error_message = "server-side encryption must be on for every table."
  }
}

run "only_the_two_documented_indexes_exist" {
  command = plan

  assert {
    condition = (
      length(aws_dynamodb_table.users.global_secondary_index) == 1 &&
      length(aws_dynamodb_table.labs.global_secondary_index) == 0 &&
      length(aws_dynamodb_table.sessions.global_secondary_index) == 1 &&
      length(aws_dynamodb_table.activity.global_secondary_index) == 0
    )
    error_message = "docs/16 defines exactly two indexes. A third means an access pattern was added without updating the doc, or an index was left behind."
  }
}
