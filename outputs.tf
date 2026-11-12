output "role_arn" {
  description = "ARN of the launcher role: the CI_ROLE_ARN secret of hatchrun-ci."
  value       = aws_iam_role.launcher.arn
}

output "artifacts_bucket" {
  description = "Name of the artifacts and cache bucket: the ARTIFACTS_BUCKET variable of hatchrun-ci."
  value       = aws_s3_bucket.artifacts.id
}

output "launch_template_name" {
  description = "Name of the runner launch template."
  value       = aws_launch_template.runner.name
}

output "vpc_id" {
  description = "ID of the runner VPC."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "IDs of the runner subnets, by key (a, b, c, d)."
  value       = { for key, subnet in aws_subnet.this : key => subnet.id }
}

output "security_group_id" {
  description = "ID of the runner security group."
  value       = aws_security_group.runners.id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider the launcher role trusts."
  value       = local.oidc_provider_arn
}
