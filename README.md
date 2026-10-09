# terraform-aws-hatchrun

Terraform module that deploys [hatchrun](https://github.com/hatchrun/hatchrun)
into your AWS account: launch template, IAM roles, security groups, an
optional public-subnet VPC (no NAT gateway charges), the Actions cache
bucket, a CloudWatch dashboard, and the scaler on AWS Fargate.

The scaler can run on Cloudflare Containers instead, through the
`modules/scaler-cloudflare` submodule, leaving nothing but the runners in
your AWS account.

Status: early development, not ready for production.

## Licence

Apache License, Version 2.0. See [LICENSE](LICENSE).
