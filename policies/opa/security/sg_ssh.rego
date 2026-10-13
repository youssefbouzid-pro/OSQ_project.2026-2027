package main

import rego.v1

ssh_port := 22

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "aws_security_group"
  rc.change.action in {"create", "update"}
  some ingress in rc.change.after.ingress
  covers_ssh(ingress)
  reaches_all_internet(ingress)
  msg := sprintf(
    "SEC-001 %s allows SSH (22/tcp) from the public internet (%v). Fix: restrict cidr_blocks to 100.64.0.0/10 (Tailscale) or a trusted range.",
    [rc.address, ingress.cidr_blocks],
  )
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "aws_security_group_rule"
  rc.change.action in {"create", "update"}
  rc.change.after.type == "ingress"
  covers_ssh(rc.change.after)
  reaches_all_internet(rc.change.after)
  msg := sprintf(
    "SEC-001 %s opens SSH (22/tcp) to the public internet. Fix: restrict cidr_blocks to 100.64.0.0/10 (Tailscale) or a trusted range.",
    [rc.address],
  )
}

covers_ssh(block) if {
  block.protocol == "-1"
}

covers_ssh(block) if {
  block.protocol == "tcp"
  block.from_port <= ssh_port
  block.to_port >= ssh_port
}

reaches_all_internet(block) if {
  block.cidr_blocks[_] == "0.0.0.0/0"
}

reaches_all_internet(block) if {
  block.ipv6_cidr_blocks[_] == "::/0"
}
