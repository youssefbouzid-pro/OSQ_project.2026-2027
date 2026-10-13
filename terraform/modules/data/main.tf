# DynamoDB tables defined in docs/16-api-and-data-model.md.
#
# Primary keys and the two access-pattern indexes:
#
#   users     hash userId     + GSI by-token-hash  (tokenHash)
#   labs      hash labId
#   sessions  hash sessionId  + GSI by-user        (userId, createdAt)
#   activity  hash eventId
#
# Point-in-time recovery is on for every table because the sessions and
# activity tables are the audit trail. Billing is on-demand: the PoC is
# free-tier friendly and traffic is bursty (docs/14).

resource "aws_dynamodb_table" "users" {
  name         = "${var.name_prefix}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "tokenHash"
    type = "S"
  }

  global_secondary_index {
    name            = "by-token-hash"
    hash_key        = "tokenHash"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

resource "aws_dynamodb_table" "labs" {
  name         = "${var.name_prefix}-labs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "labId"

  attribute {
    name = "labId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

resource "aws_dynamodb_table" "sessions" {
  name         = "${var.name_prefix}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"

  attribute {
    name = "sessionId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "by-user"
    hash_key        = "userId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # No DynamoDB TTL: terminated sessions must survive for audit history
  # (docs/05, docs/04). Retention is a process concern, not a TTL one.
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

resource "aws_dynamodb_table" "activity" {
  name         = "${var.name_prefix}-activity"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "eventId"

  attribute {
    name = "eventId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}
