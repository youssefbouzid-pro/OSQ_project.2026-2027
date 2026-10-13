package main

import rego.v1

test_allow_active_trail if {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "aws_cloudtrail.main",
      "type": "aws_cloudtrail",
      "change": {
        "action": "create",
        "after": {
          "enable_logging": true,
          "enable_log_file_validation": true,
          "is_multi_region_trail": true,
        },
      },
    }],
  }
}

test_deny_disabled_trail if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_cloudtrail.main",
      "type": "aws_cloudtrail",
      "change": {
        "action": "create",
        "after": {
          "enable_logging": false,
          "enable_log_file_validation": true,
        },
      },
    }],
  }
  count(denied) == 1
}

test_deny_trail_without_log_file_validation if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_cloudtrail.main",
      "type": "aws_cloudtrail",
      "change": {
        "action": "create",
        "after": {
          "enable_logging": true,
          "enable_log_file_validation": false,
        },
      },
    }],
  }
  count(denied) == 1
}

test_ignore_trail_destroy if {
  # Tearing a trail down is an explicit operator action, not a policy
  # violation; the plan still shows it, and the human still decides.
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "aws_cloudtrail.main",
      "type": "aws_cloudtrail",
      "change": {
        "action": "delete",
        "before": {
          "enable_logging": false,
          "enable_log_file_validation": false,
        },
        "after": null,
      },
    }],
  }
}
