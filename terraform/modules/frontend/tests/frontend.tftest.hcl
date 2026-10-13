# Offline tests for the frontend module.
#
# The property worth pinning here is that the site is private. A static
# bucket is the easiest thing in the stack to leave public by accident,
# and the mistake is invisible until someone finds the bucket.

mock_provider "aws" {
  # Same reason as the api module: a mocked policy document no longer
  # parses, and the bucket policy resource would take every run down.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "cloudybttounsi-test"
  source_dir  = "../../../frontend"
  tags        = { Project = "cloudybttounsi" }
}

run "bucket_is_not_public" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.site.block_public_acls == true &&
      aws_s3_bucket_public_access_block.site.block_public_policy == true &&
      aws_s3_bucket_public_access_block.site.ignore_public_acls == true &&
      aws_s3_bucket_public_access_block.site.restrict_public_buckets == true
    )
    error_message = "all four public-access blocks must be on. Any one of them off is enough to expose the bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.site.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "BucketOwnerEnforced disables ACLs entirely, so a stray ACL cannot reopen the bucket."
  }
}

run "bucket_is_encrypted_and_versioned" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.site.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "the site bucket must be encrypted with a customer-managed KMS key, matching the rest of the stack."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.site.versioning_configuration).status == "Enabled"
    error_message = "versioning must be on so a bad deploy is one command from being rolled back."
  }
}

run "site_is_served_over_https_only" {
  command = plan

  assert {
    condition     = one(aws_cloudfront_distribution.site.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "the distribution must redirect to HTTPS. docs/11 requires tokens to travel only over TLS."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021"
    error_message = "pin the TLS floor to 1.2. The default certificate is in use until a domain exists, but the floor must still be stated."
  }
}

run "distribution_reads_from_a_private_origin" {
  command = plan

  # The origin's origin_access_control_id is a computed reference, so it
  # is unknown under a mocked provider. What is known is the OAC itself,
  # which is the thing that makes the bucket unreachable from anywhere
  # except this distribution.
  assert {
    condition = (
      aws_cloudfront_origin_access_control.site.origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.site.signing_protocol == "sigv4" &&
      aws_cloudfront_origin_access_control.site.signing_behavior == "always"
    )
    error_message = "the origin access control must sign S3 requests with SigV4, always. Without it the distribution falls back to a public bucket policy."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.enabled == true
    error_message = "the distribution must be enabled."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.default_root_object == "index.html"
    error_message = "a bare CloudFront URL must serve the app shell."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.price_class == "PriceClass_100"
    error_message = "docs/12 puts the PoC on the cheapest edge footprint; a wider price class is a cost decision, not a default."
  }
}

run "cache_behaviour_is_get_head_only" {
  command = plan

  assert {
    condition = (
      toset(one(aws_cloudfront_distribution.site.default_cache_behavior).allowed_methods) == toset(["GET", "HEAD"]) &&
      toset(one(aws_cloudfront_distribution.site.default_cache_behavior).cached_methods) == toset(["GET", "HEAD"])
    )
    error_message = "a static site serves no writes; allowing anything beyond GET and HEAD is unnecessary attack surface."
  }
}
