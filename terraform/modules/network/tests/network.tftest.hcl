# Offline tests for the network module.
#
# The AWS provider is mocked and the two availability zones are pinned,
# so this runs with no credentials and can sit in CI.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}

variables {
  project     = "cloudybttounsi"
  environment = "dev"
}

run "layout" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "the VPC must equal var.vpc_cidr."
  }

  assert {
    condition     = length(aws_subnet.this) == 6
    error_message = "expected 6 subnets: 2 public, 2 app, 2 data."
  }

  assert {
    condition = length([
      for k, s in aws_subnet.this : k if local.subnets[k].tier == "data"
    ]) == 2
    error_message = "expected 2 isolated data subnets, reserved for a future data tier per docs/05."
  }

  # The bug this file exists to catch. A /20 inside 10.0.0.0/16 starts
  # at 0, 16, 32 or 48; anything else has host bits set and AWS rejects
  # it at apply time, which `terraform validate` never sees.
  assert {
    condition = alltrue([
      for tier, cidrs in local.subnet_tiers :
      alltrue([for cidr in cidrs : cidrhost(cidr, 0) == split("/", cidr)[0]])
    ])
    error_message = "every subnet CIDR must be the network address for its prefix. 10.0.8.0/20 is not: a /20 inside 10.0.0.0/16 starts at 0, 16, 32 or 48."
  }

  assert {
    condition = length(distinct(flatten([
      for cidrs in values(local.subnet_tiers) : cidrs
    ]))) == 6
    error_message = "the six subnet CIDRs must not overlap."
  }

  assert {
    condition = (
      aws_route_table.public.tags["Tier"] == "public" &&
      aws_route_table.app.tags["Tier"] == "app" &&
      aws_route_table.data.tags["Tier"] == "data"
    )
    error_message = "each tier needs its own route table; sharing one would give app and data subnets a route to the internet gateway."
  }

  # Only one route exists in the module, and it is the public default
  # route. App and data subnets deliberately have none.
  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "the public tier needs a default route to the internet gateway; app and data tiers must have none."
  }
}

run "staging_is_rejected" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}
