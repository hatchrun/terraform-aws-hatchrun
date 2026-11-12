# terraform-aws-hatchrun

Terraform module for the AWS account that runs hatchrun CI jobs. It is a port of `deploy/cloudformation/ci-account.yaml` in the hatchrun repo.

Deploy it once in `us-east-1`. The module creates:

* A VPC with public subnets, an internet gateway, and an S3 gateway endpoint.
* A runner security group with no inbound rules and no outbound port 25.
* The `hatchrun-ci-runner` launch template (IMDSv2 required, hop limit 1, encrypted gp3 root volume).
* An artifacts and cache S3 bucket with TLS-only policy and lifecycle rules.
* An IAM OIDC provider for `oidc.hatchrun.io` and the launcher role that hatchrun CI assumes.

hatchrun CI takes `role_arn` as its `CI_ROLE_ARN` secret and `artifacts_bucket` as `ARTIFACTS_BUCKET`. It finds the launch template by name and the subnets by their `hatchrun:tenant` tag.

## Usage

```hcl
module "hatchrun" {
  source  = "github.com/hatchrun/terraform-aws-hatchrun?ref=v1.0.0"
}
```

With non-default settings:

```hcl
module "hatchrun" {
  source  = "github.com/hatchrun/terraform-aws-hatchrun?ref=v1.0.0"
  name    = "hatchrun-ci"
  tenant  = "hatchrun-ci"
  vpc_cidr = "10.40.0.0/16"
  tags = {
    owner = "ci-team"
  }
}
```

## Inputs

| Name | Type | Default | Description |
| ---- | ---- | ------- | ----------- |
| `name` | `string` | `"hatchrun-ci"` | Prefix for resource names and the Name tags. |
| `tenant` | `string` | `"hatchrun-ci"` | Value of the `hatchrun:tenant` tag and the tenant in the OIDC subject (`tenant:<tenant>`). |
| `vpc_cidr` | `string` | `"10.40.0.0/16"` | CIDR block of the runner VPC. Each subnet gets a quarter of it. |
| `availability_zones` | `list(string)` | `[]` | Zones for the public subnets, one subnet each, at most four. Empty takes the first three zones of the region. |
| `oidc_issuer` | `string` | `"https://oidc.hatchrun.io"` | The issuer whose tokens the launcher role accepts. |
| `oidc_provider_arn` | `string` | `null` | ARN of an existing IAM OIDC provider. Null creates it. |
| `role_name` | `string` | `null` | Name of the launcher role. Null names it `<name>-launcher`. |
| `security_group_name` | `string` | `null` | Name of the runner security group. Null names it `<name>-runners`. |
| `artifacts_bucket_name` | `string` | `null` | Name of the artifacts and cache bucket. Null lets AWS pick a name starting with `<name>-artifacts-`. |
| `root_volume_size` | `number` | `30` | Size of each runner root volume in GiB. |
| `root_device_name` | `string` | `"/dev/sda1"` | Device name of the runner root volume. It must match the root device of the AMI the runners boot. |
| `tags` | `map(string)` | `{}` | Tags added to every resource. |

## Outputs

| Name | Description |
| ---- | ----------- |
| `role_arn` | ARN of the launcher role: the `CI_ROLE_ARN` secret of hatchrun CI. |
| `artifacts_bucket` | Name of the artifacts and cache bucket: the `ARTIFACTS_BUCKET` variable of hatchrun CI. |
| `launch_template_name` | Name of the runner launch template. |
| `vpc_id` | ID of the runner VPC. |
| `subnet_ids` | IDs of the runner subnets, by key (`a`, `b`, `c`, `d`). |
| `security_group_id` | ID of the runner security group. |
| `oidc_provider_arn` | ARN of the IAM OIDC provider the launcher role trusts. |

## Adopting resources from the CloudFormation stack

The live account is already imported into this module. To repeat the adoption for a stack that still exists, follow these steps.

1. Set DeletionPolicy Retain and UpdateReplacePolicy Retain on every resource of the CloudFormation stack, applied with a change set. This keeps each live resource when the stack goes away.
2. Delete the stack. Every resource stays in the account.
3. Import each resource with an `import` block that uses the module address, for example `module.hatchrun.aws_vpc.this`. Set the inputs below first so the plan keeps each resource instead of replacing it, then run `terraform plan` and `terraform apply`. The apply records the imports.

Set these inputs to the CloudFormation values:

* `role_name`: the `LauncherRole` physical ID, for example `hatchrun-ci-LauncherRole-ABC`.
* `security_group_name`: the `RunnerSecurityGroup` group NAME (GroupName, for example `hatchrun-ci-RunnerSecurityGroup-XXXX`), not the `sg-` ID.
* `artifacts_bucket_name`: the `ArtifactsBucket` physical ID.
* `availability_zones`: the zones of the existing subnets. The module makes one subnet per zone with the same `/18` CIDRs, so the plan keeps each subnet.
* Leave `oidc_provider_arn` unset and import `aws_iam_openid_connect_provider.hatchrun[0]` below, so the provider stays managed by this module.

Import every resource:

| Address | Import ID |
| ------- | --------- |
| `module.hatchrun.aws_vpc.this` | VPC ID (`vpc-...`) |
| `module.hatchrun.aws_internet_gateway.this` | Internet gateway ID (`igw-...`) |
| `module.hatchrun.aws_route_table.this` | Route table ID (`rtb-...`) |
| `module.hatchrun.aws_route.default` | `<rtb-id>_0.0.0.0/0` |
| `module.hatchrun.aws_subnet.this["a"]` (and `"b"`, `"c"`, ...) | Subnet ID (`subnet-...`) per zone |
| `module.hatchrun.aws_route_table_association.this["a"]` (and `"b"`, `"c"`, ...) | `<subnet-id>/<rtb-id>` per zone |
| `module.hatchrun.aws_vpc_endpoint.s3` | Endpoint ID (`vpce-...`) |
| `module.hatchrun.aws_security_group.runners` | Security group ID (`sg-...`) |
| `module.hatchrun.aws_vpc_security_group_egress_rule.runners["tcp-below-25"]` | Rule ID (`sgr-...`) |
| `module.hatchrun.aws_vpc_security_group_egress_rule.runners["tcp-above-25"]` | Rule ID (`sgr-...`) |
| `module.hatchrun.aws_vpc_security_group_egress_rule.runners["udp"]` | Rule ID (`sgr-...`) |
| `module.hatchrun.aws_vpc_security_group_egress_rule.runners["icmp"]` | Rule ID (`sgr-...`) |
| `module.hatchrun.aws_launch_template.runner` | Template ID (`lt-...`) |
| `module.hatchrun.aws_s3_bucket.artifacts` | Bucket name |
| `module.hatchrun.aws_s3_bucket_ownership_controls.artifacts` | Bucket name |
| `module.hatchrun.aws_s3_bucket_public_access_block.artifacts` | Bucket name |
| `module.hatchrun.aws_s3_bucket_server_side_encryption_configuration.artifacts` | Bucket name |
| `module.hatchrun.aws_s3_bucket_lifecycle_configuration.artifacts` | Bucket name |
| `module.hatchrun.aws_s3_bucket_policy.artifacts` | Bucket name |
| `module.hatchrun.aws_iam_openid_connect_provider.hatchrun[0]` | Provider ARN |
| `module.hatchrun.aws_iam_role.launcher` | Role name |
| `module.hatchrun.aws_iam_role_policy.launcher` | `<role-name>:run-ci-jobs` |

The bucket has `prevent_destroy`, so Terraform refuses to delete it. After import, `terraform plan` must show no replacement. Rename only through the inputs above.

## Security notes

Runners get no instance profile. The launcher role has no `iam:PassRole`,
and the `NoInstanceProfile` statement refuses any launch that carries a
profile, including one added through a new launch template version.

EC2 checks that statement when an instance launches under the role's
own call, which is every launch hatchrun makes: it creates instant
fleets only. A `maintain` or `request` fleet relaunches instances later
through the `AWSServiceRoleForEC2Fleet` service-linked role, and AWS
does not check the caller's policy again for those launches. No IAM
condition key limits `CreateFleet` to the instant type. The launcher
role cannot create that service-linked role, so in an account where it
does not exist such fleets cannot start. Keep it that way in the
runner account, and keep instance profiles out of it.

## Licence

Apache License, Version 2.0. See [LICENSE](LICENSE).
