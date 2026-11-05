# terraform-aws-hatchrun (retired)

This module deployed the hatchrun self-hosted scaler into an AWS account:
launch template, IAM roles, security groups, an optional VPC, the Actions
cache bucket, a CloudWatch dashboard and the scaler on AWS Fargate.

The self-hosted GitHub Actions runner product ended on 2026-11-05 and this
module is no longer maintained.

hatchrun is now its own CI. It needs no AWS setup on your side: nothing to
deploy, no roles to create.

## Tear down

If you applied this module, remove everything it created from the
directory that holds your configuration:

```sh
terraform destroy
```

## Licence

Apache License, Version 2.0. See [LICENSE](LICENSE).
