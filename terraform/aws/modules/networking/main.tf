# ============================================================
# HomeEase VPC — mirrors terraform/azure/modules/networking's shape
# (one network boundary, subnets split by role) using AWS's native
# building blocks instead of a VNet/NSG.
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "vpc-homeease-${var.environment}"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "igw-homeease-${var.environment}"
  })
}

# ============================================================
# PUBLIC SUBNETS — one per AZ. Only thing that lives here is the
# ingress-nginx Service's Network Load Balancer (tagged below so the
# AWS Load Balancer / VPC CNI machinery can discover it automatically)
# and the single NAT Gateway. EKS nodes are NOT here.
# ============================================================

resource "aws_subnet" "public" {
  for_each = { for idx, cidr in var.public_subnet_cidrs : local.azs[idx] => cidr }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "snet-public-${var.environment}-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  })
}

# ============================================================
# PRIVATE SUBNETS — EKS worker nodes live here, with no public IP and
# no direct route to the internet except through the NAT Gateway.
# ============================================================

resource "aws_subnet" "private" {
  for_each = { for idx, cidr in var.private_subnet_cidrs : local.azs[idx] => cidr }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name                                        = "snet-private-${var.environment}-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  })
}

# ============================================================
# NAT GATEWAY — deliberately ONE, not one per AZ.
#
# A NAT Gateway per AZ (the normal production recommendation, so a
# single AZ outage doesn't take every private subnet's egress with
# it) is ~$32/month EACH. This is a dev environment mirroring a
# single-region AKS cluster that has the same single-NAT-equivalent
# blast radius (Azure's outbound_type = loadBalancer routes through
# one Standard Load Balancer, not one per zone). One NAT Gateway here
# matches that cost/resilience trade-off instead of silently paying
# 2x for redundancy nothing else in this stack has yet. Revisit this
# specifically (not the rest of the module) for a real prod stack.
# ============================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "eip-nat-homeease-${var.environment}"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(var.tags, {
    Name = "nat-homeease-${var.environment}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ============================================================
# ROUTING
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "rt-public-${var.environment}"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "rt-private-${var.environment}"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
