data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  subnet_tiers = {
    public = var.public_subnet_cidrs
    app    = var.app_subnet_cidrs
    data   = var.data_subnet_cidrs
  }

  subnets = merge([
    for tier, cidrs in local.subnet_tiers : {
      for i, cidr in cidrs : "${tier}-${i}" => {
        cidr  = cidr
        tier  = tier
        az    = local.azs[i % length(local.azs)]
        index = i
      }
    }
  ]...)

  common_tags = merge(var.tags, {
    Project   = var.project
    Component = "network"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-vpc"
    Environment = var.environment
  })
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-default-sg"
    Environment = var.environment
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-igw"
    Environment = var.environment
  })
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-${each.value.tier}-${each.value.index}"
    Environment = var.environment
    Tier        = each.value.tier
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-public-rt"
    Environment = var.environment
    Tier        = "public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-app-rt"
    Environment = var.environment
    Tier        = "app"
  })
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name        = "${var.project}-${var.environment}-data-rt"
    Environment = var.environment
    Tier        = "data"
  })
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id = each.value.id
  route_table_id = (
    local.subnets[each.key].tier == "public" ? aws_route_table.public.id :
    local.subnets[each.key].tier == "app" ? aws_route_table.app.id :
    aws_route_table.data.id
  )
}
