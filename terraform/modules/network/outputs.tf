output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "Public subnets: labs, API edge, ops host. Direct IGW egress, no NAT."
  value       = { for k, s in aws_subnet.this : k => s.id if local.subnets[k].tier == "public" }
}

output "app_subnet_ids" {
  description = "Private app subnets: backend Lambda. No internet route."
  value       = { for k, s in aws_subnet.this : k => s.id if local.subnets[k].tier == "app" }
}

output "data_subnet_ids" {
  description = "Isolated data subnets reserved for a future data tier. No route to IGW or NAT. The PoC control plane uses DynamoDB (docs/14)."
  value       = { for k, s in aws_subnet.this : k => s.id if local.subnets[k].tier == "data" }
}

output "public_subnet_cidrs" {
  description = "CIDRs of public subnets."
  value       = { for k, s in aws_subnet.this : k => s.cidr_block if local.subnets[k].tier == "public" }
}

output "app_subnet_cidrs" {
  description = "CIDRs of app subnets."
  value       = { for k, s in aws_subnet.this : k => s.cidr_block if local.subnets[k].tier == "app" }
}

output "data_subnet_cidrs" {
  description = "CIDRs of data subnets."
  value       = { for k, s in aws_subnet.this : k => s.cidr_block if local.subnets[k].tier == "data" }
}
