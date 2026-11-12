resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_route" "default" {
  route_table_id         = aws_route_table.this.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Public subnets in each zone: no NAT gateway to pay for, and the
# launcher tries the next subnet when a zone has no capacity. hatchrun
# finds them by their hatchrun:tenant tag.
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 2, each.value.index)
  availability_zone       = each.value.zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, local.tenant_tag, { Name = "${var.name}-${each.key}" })
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id      = each.value.id
  route_table_id = aws_route_table.this.id
}

# Artifacts go to S3 in this region over the VPC, so the bytes of an
# upload or download never leave AWS.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${local.region}.s3"
  route_table_ids   = [aws_route_table.this.id]

  tags = var.tags
}
