# Offline tests for the governance module.
#
# A trail that exists but does not validate its log files is not an audit
# trail, and a multi-region trail that silently stops logging is worse
# than none, because it looks like coverage. Both are single booleans
# that are easy to flip in a refactor and impossible to notice in a
# console screenshot, so they are what these tests pin down.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      id = "111111111111"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix        = "osq-test"
  log_retention_days = 365
  tags               = { Project = "osq" }
}

run "trail_is_a_real_audit_trail" {
  command = plan

  # docs/10 control GOV-001: CloudTrail must remain enabled, and it must
  # be worth reading when it does.
  assert {
    condition     = aws_cloudtrail.main.enable_logging == true
    error_message = "GOV-001 in docs/10 requires CloudTrail to be enabled. A disabled trail looks identical to an enabled one in most dashboards."
  }

  assert {
    condition     = aws_cloudtrail.main.enable_log_file_validation == true
    error_message = "log file validation is what makes this an audit trail rather than a log: it produces a digest per file so a deleted or edited entry is detectable."
  }

  assert {
    condition     = aws_cloudtrail.main.is_multi_region_trail == true
    error_message = "a single-region trail makes any change made outside the home region invisible."
  }

  assert {
    condition     = aws_cloudtrail.main.include_global_service_events == true
    error_message = "global service events cover IAM, which is where the interesting changes happen."
  }

  assert {
    condition     = aws_cloudtrail.main.name == "osq-test-trail"
    error_message = "the trail name is what the KMS key policy scopes its encryption context to; a rename without a matching key policy change stops the trail writing."
  }
}

run "trail_logs_are_encrypted" {
  command = plan

  # kms_key_id is a reference to the key ARN, so it is unknown under a
  # mocked provider. What is known is the key the module builds for it.
  assert {
    condition     = aws_kms_key.trail.enable_key_rotation == true
    error_message = "the trail key must rotate; a long-lived audit key is the one an attacker most wants."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.trail.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "log objects at rest must be KMS encrypted, matching the rest of the stack."
  }
}

run "log_bucket_is_private" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.trail.block_public_acls == true &&
      aws_s3_bucket_public_access_block.trail.block_public_policy == true &&
      aws_s3_bucket_public_access_block.trail.ignore_public_acls == true &&
      aws_s3_bucket_public_access_block.trail.restrict_public_buckets == true
    )
    error_message = "the audit log bucket must not be reachable publicly under any of the four mechanisms."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.trail.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "BucketOwnerEnforced disables ACLs so a stray ACL cannot reopen the bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.trail.versioning_configuration).status == "Enabled"
    error_message = "versioning must be on; an audit log object must not be removable by a single PutObject."
  }
}

run "log_objects_are_not_expired" {
  command = plan

  # Only noncurrent versions expire. A current audit log object must
  # never be deleted by a lifecycle rule, only by the retention policy
  # an operator applies deliberately.
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.trail.rule).noncurrent_version_expiration[0].noncurrent_days == 365
    error_message = "noncurrent versions must be cleaned up, or versioning turns the audit bucket into an unbounded cost sink."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.trail.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 1
    error_message = "incomplete multipart uploads must be aborted, or a half-written log object sits in the bucket indefinitely."
  }
}

run "trail_events_are_queryable" {
  command = plan

  # CloudTrail writes to S3, but S3 cannot answer "did the trail stop?".
  # docs/17 calls for CloudTrail alerts, and that needs a Logs stream.
  assert {
    condition     = aws_cloudwatch_log_group.trail.name == "/aws/cloudtrail/osq-test-trail"
    error_message = "the log group name is the one CloudTrail expects; a mismatch means events are silently dropped."
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail.retention_in_days == 365
    error_message = "the trail log group must keep the same retention as the log objects, or the queryable copy outlives or underlives the audit copy."
  }

  assert {
    condition     = aws_sns_topic.audit.name == "osq-test-audit"
    error_message = "docs/17 calls for CloudTrail alerts, which need a topic to publish to. Subscriptions are an operator decision; the topic is not."
  }
}

run "guardduty_is_on" {
  command = plan

  assert {
    condition     = length(aws_guardduty_detector.main) == 1 && aws_guardduty_detector.main[0].enable == true
    error_message = "a detector that exists but is disabled reports nothing and gives false assurance."
  }
}

run "guardduty_can_be_opted_out" {
  command = plan

  variables {
    enable_guardduty = false
  }

  assert {
    condition     = length(aws_guardduty_detector.main) == 0
    error_message = "opting out must remove the detector entirely rather than leave a disabled one behind."
  }
}

run "short_retention_is_rejected" {
  command = plan

  variables {
    log_retention_days = 30
  }

  expect_failures = [var.log_retention_days]
}
