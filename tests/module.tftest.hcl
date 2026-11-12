mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  # The mock fills policy JSON with random strings; these keep it valid.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = length(aws_subnet.this) == 3
    error_message = "Three subnets by default."
  }

  assert {
    condition = (
      aws_subnet.this["a"].cidr_block == "10.40.0.0/18" &&
      aws_subnet.this["b"].cidr_block == "10.40.64.0/18" &&
      aws_subnet.this["c"].cidr_block == "10.40.128.0/18"
    )
    error_message = "Subnets are the first three /18s of the VPC."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.this : s.map_public_ip_on_launch && s.tags["hatchrun:tenant"] == "hatchrun-ci"])
    error_message = "Every subnet is public and carries the tenant tag."
  }

  assert {
    condition     = aws_launch_template.runner.name == "hatchrun-ci-runner"
    error_message = "hatchrun finds the template by this name."
  }

  assert {
    condition = (
      aws_launch_template.runner.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.runner.metadata_options[0].http_put_response_hop_limit == 1
    )
    error_message = "IMDSv2 with hop limit 1."
  }

  assert {
    condition     = aws_launch_template.runner.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Root volumes are encrypted; the role only launches encrypted volumes."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.hatchrun) == 1
    error_message = "The provider is created when none is given."
  }

  assert {
    condition     = aws_iam_role.launcher.name == "hatchrun-ci-launcher"
    error_message = "Default role name."
  }

  assert {
    condition = (
      toset([for s in data.aws_iam_policy_document.launcher.statement : s.sid]) == toset([
        "List", "LaunchInstances", "LaunchVolumes", "LaunchOwnImages",
        "LaunchNetwork", "LaunchFromTemplate", "LaunchFleet",
        "RunnerTemplateVersions", "TagAtLaunch", "ArtifactObjects",
        "CacheObjects", "ManageOwnInstances", "ManagePoolInstances",
        "TagPoolInstances", "UntagPoolInstances", "NoInstanceProfile",
      ])
    )
    error_message = "The launcher policy has exactly the expected statements."
  }

  assert {
    condition = (
      one([for s in data.aws_iam_policy_document.launcher.statement : s.effect if s.sid == "NoInstanceProfile"]) == "Deny"
    )
    error_message = "Launches with an instance profile are refused."
  }

  assert {
    condition     = aws_launch_template.runner.block_device_mappings[0].device_name == "/dev/sda1"
    error_message = "Default root device matches Ubuntu runner AMIs."
  }
}

run "port_25_is_closed" {
  command = plan

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_egress_rule.runners :
      rule.ip_protocol != "tcp" || rule.to_port < 25 || rule.from_port > 25
    ])
    error_message = "No TCP egress rule covers port 25."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.runners) == 4
    error_message = "Four egress rules: TCP below 25, TCP above 25, UDP, ICMP."
  }
}

run "existing_resources" {
  command = plan

  variables {
    availability_zones    = ["us-east-1a", "us-east-1b"]
    oidc_provider_arn     = "arn:aws:iam::123456789012:oidc-provider/oidc.hatchrun.io"
    role_name             = "hatchrun-ci-LauncherRole-ABC"
    security_group_name   = "hatchrun-ci-RunnerSecurityGroup-XYZ"
    artifacts_bucket_name = "hatchrun-ci-artifactsbucket-123"
  }

  assert {
    condition     = length(aws_subnet.this) == 2 && aws_subnet.this["b"].availability_zone == "us-east-1b"
    error_message = "One subnet per given zone."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.hatchrun) == 0
    error_message = "No provider is created when one is given."
  }

  assert {
    condition = (
      aws_iam_role.launcher.name == "hatchrun-ci-LauncherRole-ABC" &&
      aws_security_group.runners.name == "hatchrun-ci-RunnerSecurityGroup-XYZ" &&
      aws_s3_bucket.artifacts.bucket == "hatchrun-ci-artifactsbucket-123"
    )
    error_message = "Given names are kept, so existing resources import without replacement."
  }
}

run "custom_tenant_and_root_device" {
  command = plan

  variables {
    tenant           = "acme"
    root_device_name = "/dev/xvda"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.trust.statement : anytrue([
        for c in s.condition : c.test == "StringEquals" && contains(c.values, "tenant:acme")
      ])
    ])
    error_message = "The launcher role trusts tenant:acme."
  }

  assert {
    condition     = aws_launch_template.runner.block_device_mappings[0].device_name == "/dev/xvda"
    error_message = "The launch template uses root_device_name."
  }
}

run "fewer_zones_than_default" {
  command = plan

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "Zone default takes min(3, available)."
  }
}

run "too_many_zones" {
  command = plan

  variables {
    availability_zones = ["a", "b", "c", "d", "e"]
  }

  expect_failures = [var.availability_zones]
}
