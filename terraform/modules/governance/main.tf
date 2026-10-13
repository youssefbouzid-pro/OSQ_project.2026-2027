# Governance plane: the audit trail docs/10 calls for.
#
# docs/10 lists CloudTrail (API activity audit) as control GOV-001 and
# AWS Config (configuration and drift checks). Config is deliberately
# out of scope here; CloudTrail is the one an auditor asks for first,
# and it is the one that catches "someone changed the security group at
# 2am" without any rule authoring.
#
# GuardDuty is not named in docs/10 or docs/11. It is included as
# defence in depth: it costs nothing while the account is idle, needs no
# rule authoring, and would catch credential abuse or an instance
# joining a known-bad command-and-control domain, which is a real path
# for a lab environment that reaches the internet over HTTPS.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.id
  partition  = data.aws_partition.current.partition

  # CloudTrail names the trail in the encryption context, so the key
  # policy has to match it exactly. Built here rather than referenced
  # from the trail, because the key is a dependency of the trail.
  trail_name = "${var.name_prefix}-trail"
  trail_arn  = "arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/${local.trail_name}"

  s3_key_prefix = "cloudtrail"
}

# ---------------------------------------------------------------------------
# CloudTrail
# ---------------------------------------------------------------------------

resource "aws_kms_key" "trail" {
  description             = "${var.name_prefix} CloudTrail log encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "trail" {
  name          = "alias/${var.name_prefix}-trail"
  target_key_id = aws_kms_key.trail.key_id
}

# CloudTrail writes with its service principal, so the key policy must
# name that principal and scope it to this trail's encryption context.
# Without the condition any trail in the account could use the key.
data "aws_iam_policy_document" "trail_key" {
  # checkov:skip=CKV_AWS_356: The account root statement is `kms:*` on
  # `*`. That is not a permissions leak, it is how a KMS key policy has
  # to be written: without the root principal the key cannot be
  # administered or deleted by anyone, including the account owner. The
  # CloudTrail and SNS statements below it are both scoped, the first by
  # encryption context and the second by caller account and topic ARN.
  # checkov:skip=CKV_AWS_109: Follows from CKV_AWS_356, same statement.
  # checkov:skip=CKV_AWS_111: Follows from CKV_AWS_356, same statement.

  statement {
    sid    = "AllowAccountRoot"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudTrailEncrypt"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = [local.trail_arn]
    }
  }

  # The audit notification topic is encrypted with this key too, so SNS
  # has to be able to use it. Scoped to this account's topics rather than
  # left open.
  statement {
    sid    = "AllowSNSEncrypt"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:sns:arn"
      values   = ["arn:${local.partition}:sns:*:${local.account_id}:*"]
    }
  }
}

resource "aws_kms_key_policy" "trail" {
  key_id = aws_kms_key.trail.id
  policy = data.aws_iam_policy_document.trail_key.json
}

resource "aws_s3_bucket" "trail" {
  # AWS-generated name: the bucket namespace is global and a collision
  # would be an apply-time failure with no local fix.
  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.trail.arn
    }
  }
}

# Audit logs are retained for the configured window and then dropped, but
# current versions are never expired: deleting a trail object must take a
# deliberate action, not a lifecycle rule.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/${local.s3_key_prefix}/AWSLogs/${local.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail.id
  s3_key_prefix  = local.s3_key_prefix

  # Log file validation produces an digest per file so a deleted or
  # edited entry is detectable. This is the difference between a log and
  # an audit trail, and it is what GOV-001 in docs/10 actually asks for.
  enable_log_file_validation = true

  # Management events in every region. Without multi-region a change made
  # outside the home region is simply invisible.
  is_multi_region_trail         = true
  include_global_service_events = true

  enable_logging = true

  kms_key_id = aws_kms_key.trail.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_cloudwatch.arn

  sns_topic_name = aws_sns_topic.audit.name

  tags = var.tags

  depends_on = [
    aws_kms_key_policy.trail,
    aws_iam_role_policy.trail_cloudwatch,
  ]
}

# ---------------------------------------------------------------------------
# Delivery: CloudWatch Logs and the audit notification topic
# ---------------------------------------------------------------------------

# CloudTrail writes to S3, but S3 is a poor place to answer "did the
# trail stop?". A CloudWatch Logs stream makes that queryable and is what
# docs/17 means by CloudTrail alerts.
resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.trail.arn

  tags = var.tags
}

data "aws_iam_policy_document" "trail_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "trail_cloudwatch" {
  name               = "${local.trail_name}-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.trail_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "trail_cloudwatch" {
  statement {
    sid    = "WriteTrailEvents"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.trail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "trail_cloudwatch" {
  name   = "${local.trail_name}-cloudwatch"
  role   = aws_iam_role.trail_cloudwatch.id
  policy = data.aws_iam_policy_document.trail_cloudwatch.json
}

# Topic for audit alerts. Subscriptions are an operator decision, so none
# are created here; the topic is the wiring the trail needs.
resource "aws_sns_topic" "audit" {
  name              = "${var.name_prefix}-audit"
  kms_master_key_id = aws_kms_key.trail.key_id
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# GuardDuty
# ---------------------------------------------------------------------------

resource "aws_guardduty_detector" "main" {
  # checkov:skip=CKV2_AWS_3: A publishing destination is for organisation
  # or multi-account aggregation. This is a single-account PoC; findings
  # are read from the GuardDuty console or API. Add a destination when
  # there is somewhere for them to go.

  count = var.enable_guardduty ? 1 : 0

  enable = true
  tags   = var.tags
}
