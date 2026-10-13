package main

import rego.v1

test_deny_oversized_instance if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_instance.bastion",
      "type": "aws_instance",
      "change": {
        "action": "create",
        "after": {"instance_type": "m5.2xlarge"},
      },
    }],
  }
  count(denied) == 1
}

test_allow_t4g_micro if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_instance.lab",
      "type": "aws_instance",
      "change": {
        "action": "create",
        "after": {"instance_type": "t4g.micro"},
      },
    }],
  }
  count(denied) == 0
}
