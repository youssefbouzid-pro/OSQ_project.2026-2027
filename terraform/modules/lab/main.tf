data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name = var.name_prefix

  launch_template_name = var.launch_template_name != "" ? var.launch_template_name : "${local.name}-lab"

  tailscale_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:parameter${var.tailscale_auth_key_parameter_name}"

  ami_parameter_prefix = "/cloudybt/ami"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Lab security group
#
# No ingress rules at all. Learners reach the instance over Tailscale, so
# there is nothing to open on the AWS side, and policy SEC-001 keeps SSH off
# the public internet.
# ---------------------------------------------------------------------------

resource "aws_security_group" "lab" {
  name        = "${local.name}-lab"
  description = "Ephemeral learner labs. Egress only: access is over Tailscale, never the public internet."
  vpc_id      = var.vpc_id

  # Outbound is scoped to what a lab actually needs: package mirrors and
  # the Tailscale coordination server over HTTPS, DNS, and Tailscale's
  # direct UDP path. There is no ingress rule at all.
  egress {
    description      = "HTTPS for Tailscale and package mirrors"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "HTTP for package mirrors"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Tailscale direct path"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Instance role
#
# The only secret this role can read is the Tailscale auth key parameter,
# and the value is fetched at boot rather than baked into the AMI
# (docs/15 security controls).
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lab_instance" {
  name = "${local.name}-lab-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "tailscale_key" {
  name = "read-tailscale-auth-key"
  role = aws_iam_role.lab_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTailscaleAuthKey"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = local.tailscale_parameter_arn
      },
      {
        Sid      = "DecryptSecureString"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_session" {
  count = var.enable_ssm_access ? 1 : 0

  role       = aws_iam_role.lab_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "lab" {
  name = "${local.name}-lab-instance"
  role = aws_iam_role.lab_instance.name
  tags = local.tags
}

# ---------------------------------------------------------------------------
# Launch template
#
# The orchestrator overrides ImageId and InstanceType per lab at launch
# time, so the template carries the settings that must never drift:
# IMDSv2 required, an encrypted root volume deleted on termination, and
# the instance profile that can read the Tailscale key.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "lab" {
  name        = local.launch_template_name
  description = "Approved settings for CloudyBTTounsi ephemeral labs (docs/15)."

  image_id      = var.lab_ami_id
  instance_type = "t4g.micro"
  user_data     = base64encode("#!/bin/bash\n# Session-specific bootstrap is injected by the orchestrator.\n")

  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.lab.arn
  }

  vpc_security_group_ids = [aws_security_group.lab.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = 10
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = false
  }

  # Instance tags (Project, ManagedBy, SessionId, ...) are applied by the
  # orchestrator at launch because they are session-specific. They cannot
  # live here: launch-template tags would be replaced wholesale by the
  # runtime TagSpecifications.
  tags = local.tags
}

# ---------------------------------------------------------------------------
# Approved AMI parameters
#
# One SSM parameter per lab family (docs/15). Nothing is created until an
# AMI actually exists, so this module stays valid during the bake work.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "parameters" {
  description             = "${local.name} SSM parameters (approved AMIs)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "parameters" {
  name          = "alias/${local.name}-parameters"
  target_key_id = aws_kms_key.parameters.key_id
}

resource "aws_ssm_parameter" "ami" {
  for_each = var.ami_ids

  name = "${local.ami_parameter_prefix}/${each.key}"
  # SecureString under a customer-managed key even though an AMI id is
  # not a secret: Parameter Store also holds the Tailscale auth key, so
  # every parameter keeps one consistent posture.
  type   = "SecureString"
  value  = each.value
  key_id = aws_kms_key.parameters.arn

  tags = local.tags
}
