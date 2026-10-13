# Offline tests for the lab module.
#
# The lab plane is where a mistake is most expensive: a security group
# left open, or an AMI parameter readable in plaintext, is a finding that
# only shows up after a lab is running. These assertions are the ones
# Checkov cannot make on its own, because they encode intent that lives in
# this repo's docs rather than in a generic rule.

mock_provider "aws" {
  # The module interpolates these into ARNs. Left mocked they come back
  # as random strings and the managed policy ARN fails to parse.
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      id = "111111111111"
    }
  }
}

variables {
  name_prefix = "osq-test"
  vpc_id      = "vpc-0aaa1111"
  subnet_id   = "subnet-0aaa1111"
  lab_ami_id  = "ami-0approved00000000"
  ami_ids     = { linux = "ami-0approved00000000" }
  tags        = { Project = "osq" }
}

# ---------------------------------------------------------------------------
# docs/08 and docs/11: labs are reached over Tailscale, never the internet
# ---------------------------------------------------------------------------

run "security_group_declares_its_intent" {
  command = plan

  # The rule sets themselves are computed attributes, so they are unknown
  # under a mocked provider and cannot be asserted on here. That is not a
  # gap: Checkov rejects an open egress rule, and the OPA fixtures in
  # policies/tests/fixtures reject an open SSH path at plan time. What is
  # asserted here is that the module still states the constraint, so a
  # rewrite that quietly drops it has to also rewrite this line.
  assert {
    condition = (
      aws_security_group.lab.description == "Ephemeral learner labs. Egress only: access is over Tailscale, never the public internet." &&
      aws_security_group.lab.name == "osq-test-lab"
    )
    error_message = "the lab security group must keep its Tailscale-only description and its <name_prefix>-lab name."
  }

  assert {
    condition     = aws_security_group.lab.vpc_id == var.vpc_id
    error_message = "the lab security group must live in the provided VPC."
  }
}

# ---------------------------------------------------------------------------
# docs/15: the approved launch template
# ---------------------------------------------------------------------------

run "instances_cannot_spoof_their_metadata" {
  command = plan

  assert {
    condition     = aws_launch_template.lab.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required. docs/11 treats SSRF-to-metadata as a real path to the instance role."
  }

  assert {
    condition     = aws_launch_template.lab.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "hop limit of 1 keeps a container inside a lab from reaching the metadata service."
  }
}

run "root_volumes_are_encrypted" {
  command = plan

  assert {
    condition = (
      # The launch template models these as strings, not booleans.
      aws_launch_template.lab.block_device_mappings[0].ebs[0].encrypted == "true" &&
      aws_launch_template.lab.block_device_mappings[0].ebs[0].delete_on_termination == "true"
    )
    error_message = "the lab root volume must be encrypted at rest and deleted with the instance. A leftover volume is both a cost leak and a data-retention problem."
  }
}

run "default_instance_type_is_on_the_approved_list" {
  command = plan

  # The orchestrator overrides InstanceType from the lab record, so this
  # is only the fallback. It still has to be legal, because an accidental
  # launch from the template alone must not exceed the docs/12 cost model.
  assert {
    condition     = contains(["t4g.micro", "t4g.small", "t4g.medium"], aws_launch_template.lab.instance_type)
    error_message = "the launch template default must be one of the docs/12 approved types."
  }
}

# ---------------------------------------------------------------------------
# docs/12: approved AMIs are a deployment input, not a hardcoded id
# ---------------------------------------------------------------------------

run "ami_parameters_are_encrypted" {
  command = plan

  assert {
    condition = alltrue([
      for param in aws_ssm_parameter.ami :
      param.type == "SecureString"
    ])
    error_message = "AMI parameters are SecureString under a customer-managed key. Parameter Store also holds the Tailscale auth key, so every parameter keeps one consistent posture."
  }

  # key_id is a reference to the module's KMS key, so it is unknown under
  # a mocked provider. Checkov's CKV_AWS_337 covers the CMK requirement
  # against the rendered policy.

}
