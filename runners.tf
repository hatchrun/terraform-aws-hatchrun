# No inbound traffic. Outbound port 25 is blocked so a job cannot send
# mail from this address space. A security group can only allow, and
# once it lists any egress rule it drops the allow-all default, so the
# blocked port is the gap between 0-24 and 26-65535. A network ACL
# would also work but is stateless and applies to the whole subnet, so
# it needs ephemeral port rules for return traffic; the group follows
# the instance and keeps connection tracking.
resource "aws_security_group" "runners" {
  name        = coalesce(var.security_group_name, "${var.name}-runners")
  description = "hatchrun CI runners: no inbound traffic, no outbound port 25"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-runners" })
}

locals {
  egress = {
    tcp-below-25 = { protocol = "tcp", from = 0, to = 24, description = "TCP below port 25" }
    tcp-above-25 = { protocol = "tcp", from = 26, to = 65535, description = "TCP above port 25" }
    udp          = { protocol = "udp", from = 0, to = 65535, description = "All UDP" }
    icmp         = { protocol = "icmp", from = -1, to = -1, description = "All ICMP" }
  }
}

resource "aws_vpc_security_group_egress_rule" "runners" {
  for_each = local.egress

  security_group_id = aws_security_group.runners.id
  ip_protocol       = each.value.protocol
  from_port         = each.value.from
  to_port           = each.value.to
  cidr_ipv4         = "0.0.0.0/0"
  description       = each.value.description

  tags = var.tags
}

# hatchrun finds the template by name. The image and instance type come
# with each launch, which adds a version of the template with the job's
# user data and tags and deletes it after. Runners get no instance
# profile. IMDSv2 is required at launch with a hop limit of 1; hatchrun
# turns the metadata endpoint off before it hands the job its document.
resource "aws_launch_template" "runner" {
  name                                 = "${var.name}-runner"
  vpc_security_group_ids               = [aws_security_group.runners.id]
  instance_initiated_shutdown_behavior = "terminate"
  update_default_version               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = var.root_device_name

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  tags = merge(var.tags, local.tenant_tag)
}
