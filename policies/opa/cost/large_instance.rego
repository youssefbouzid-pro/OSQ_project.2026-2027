package main

import rego.v1

# Approved lab instance types, from docs/12-cost-and-ttl-model.md.
approved_instance_types := {
  "t4g.micro",
  "t4g.small",
  "t4g.medium",
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type in {"aws_instance", "aws_launch_template"}
  rc.change.action in {"create", "update"}
  instance_type := rc.change.after.instance_type
  instance_type != null
  not approved_instance_types[instance_type]
  msg := sprintf(
    "LAB-002 %s requests instance_type %s, which is not an approved lab instance type. Fix: use t4g.micro, t4g.small, or t4g.medium as listed in docs/12-cost-and-ttl-model.md.",
    [rc.address, instance_type],
  )
}
