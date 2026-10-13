# Static hosting for the web UI: a private S3 bucket behind CloudFront.
#
# The bucket is not public. CloudFront reaches it through origin access
# control, so the only reader is the distribution itself. Object uploads
# are a deploy concern (`make deploy-frontend`), not a Terraform one:
# syncing the site on every apply would bake local file timestamps into
# the plan and force a full upload on unrelated changes.
#
# docs/14 puts the web tier in CloudFront + S3 and keeps the API on a
# separate HTTP API origin. That split is preserved here: this module
# knows nothing about the API URL, and app.js talks to it at runtime.

resource "aws_s3_bucket" "site" {
  # Name is AWS-generated so the PoC never collides on the globally
  # unique bucket namespace. Read it back from the bucket output.
  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "site" {
  description             = "${var.name_prefix} static site bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "site" {
  name          = "alias/${var.name_prefix}-site"
  target_key_id = aws_kms_key.site.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.site.arn
    }
  }
}

# Versions are enabled so a bad deploy is one command away from being
# rolled back. Noncurrent versions are pure cost after a week.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name_prefix}-site"
  description                       = "Private S3 origin, reachable only from this distribution."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} web UI"
  default_root_object = "index.html"
  http_version        = "http2and3"
  price_class         = var.price_class
  wait_for_deployment = false

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Managed CachingOptimized. Hashed asset names would let us keep
    # long TTLs on CSS/JS, but index.html changes on every deploy, so a
    # single short-lived policy for the whole origin is the honest PoC
    # choice. `make deploy-frontend` invalidates after each sync.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # checkov:skip=CKV2_AWS_42: A custom ACM certificate needs a domain the
  # PoC does not own yet. The default *.cloudfront.net certificate is
  # free and still serves TLS. Revisit before any real deployment.
  # checkov:skip=CKV_AWS_68: A WAF web ACL is out of scope for the PoC.
  # Add one before exposing this to untrusted traffic.
  # checkov:skip=CKV2_AWS_47: Follows from CKV_AWS_68: no WAFv2 web ACL.
  # checkov:skip=CKV_AWS_86: Access logging needs a second, log-only
  # bucket plus a delivery pipeline. Deferred to a later hardening pass.
  # checkov:skip=CKV_AWS_310: Origin failover needs a second origin, and
  # there is only one bucket.
  # checkov:skip=CKV_AWS_174: Same root cause as CKV2_AWS_42: the default
  # *.cloudfront.net certificate carries no minimum_protocol_version that
  # this check accepts. `minimum_protocol_version` is still pinned to
  # TLSv1.2_2021 above, so a custom certificate later is a drop-in.
  # checkov:skip=CKV_AWS_374: No geo restriction is intended: the
  # catalog is meant to be reachable from anywhere a learner sits.

  # The site is one page with in-page views, but deep links such as
  # /#catalog still hit missing keys on a cold cache. Fall back to the
  # shell instead of returning an S3 XML error page.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 60
  }

  tags = var.tags
}

# AWS-managed SecurityHeadersPolicy: HSTS, X-Content-Type-Options,
# X-Frame-Options, X-XSS-Protection, referrer-policy and a
# content-security-policy suited to a same-origin static site.
data "aws_cloudfront_response_headers_policy" "security" {
  name = "SecurityHeadersPolicy"
}

data "aws_iam_policy_document" "site_read" {
  statement {
    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site_read" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_read.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

check "site_is_present" {
  assert {
    condition     = fileexists("${var.source_dir}/index.html")
    error_message = "source_dir must contain index.html; got ${var.source_dir}."
  }
}
