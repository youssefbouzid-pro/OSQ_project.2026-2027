package main

import rego.v1

# GOV-001 (docs/10): CloudTrail must remain enabled.
#
# A trail that exists but is disabled, or that does not validate its log
# files, is worse than no trail at all: it looks like coverage in a
# console screenshot and produces nothing when someone asks what
# happened. Both flags are one-line changes in a refactor and neither is
# visible until an incident.

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "aws_cloudtrail"
  rc.change.action in {"create", "update"}
  not audit_trail(rc.change.after)
  msg := sprintf(
    "GOV-001 %s is not an active audit trail. Fix: set enable_logging and enable_log_file_validation to true; a trail without log file validation cannot detect a deleted or edited entry.",
    [rc.address],
  )
}

audit_trail(trail) if {
  trail.enable_logging == true
  trail.enable_log_file_validation == true
}
