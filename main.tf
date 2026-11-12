data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.region
  account   = data.aws_caller_identity.current.account_id
  arn       = "arn:${local.partition}:ec2:${local.region}:${local.account}"

  zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, min(3, length(data.aws_availability_zones.available.names)))
  # Subnets are keyed a, b, c, d so adding a zone at the end moves none.
  subnets = { for i, zone in local.zones : substr("abcd", i, 1) => { zone = zone, index = i } }

  tenant_tag = { "hatchrun:tenant" = var.tenant }
}
