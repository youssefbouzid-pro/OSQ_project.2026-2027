package main

import rego.v1

test_deny_open_ssh if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_security_group.lab",
      "type": "aws_security_group",
      "change": {
        "action": "create",
        "after": {
          "ingress": [{
            "protocol": "tcp",
            "from_port": 22,
            "to_port": 22,
            "cidr_blocks": ["0.0.0.0/0"],
            "ipv6_cidr_blocks": [],
          }],
        },
      },
    }],
  }
  count(denied) == 1
}

test_deny_all_traffic_protocol if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_security_group_rule.open",
      "type": "aws_security_group_rule",
      "change": {
        "action": "create",
        "after": {
          "type": "ingress",
          "protocol": "-1",
          "from_port": 0,
          "to_port": 0,
          "cidr_blocks": ["0.0.0.0/0"],
          "ipv6_cidr_blocks": [],
        },
      },
    }],
  }
  count(denied) == 1
}

test_allow_tailscale_range if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_security_group.lab",
      "type": "aws_security_group",
      "change": {
        "action": "create",
        "after": {
          "ingress": [{
            "protocol": "tcp",
            "from_port": 22,
            "to_port": 22,
            "cidr_blocks": ["100.64.0.0/10"],
            "ipv6_cidr_blocks": [],
          }],
        },
      },
    }],
  }
  count(denied) == 0
}

test_allow_https_only if {
  denied := deny with input as {
    "resource_changes": [{
      "address": "aws_security_group.web",
      "type": "aws_security_group",
      "change": {
        "action": "create",
        "after": {
          "ingress": [{
            "protocol": "tcp",
            "from_port": 443,
            "to_port": 443,
            "cidr_blocks": ["0.0.0.0/0"],
            "ipv6_cidr_blocks": [],
          }],
        },
      },
    }],
  }
  count(denied) == 0
}
