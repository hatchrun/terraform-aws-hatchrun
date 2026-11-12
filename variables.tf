variable "name" {
  description = "Prefix for resource names and the Name tags."
  type        = string
  default     = "hatchrun-ci"
}

variable "tenant" {
  description = "Value of the hatchrun:tenant tag on the subnets, the launch template and every instance, and the tenant in the OIDC subject (tenant:<tenant>) the launcher role trusts."
  type        = string
  default     = "hatchrun-ci"
}

variable "vpc_cidr" {
  description = "CIDR block of the runner VPC. Each subnet gets a quarter of it."
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "Zones for the public subnets, one subnet each, at most four. Empty takes the first three zones of the region."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) <= 4
    error_message = "At most four zones: each subnet takes a quarter of vpc_cidr."
  }
}

variable "oidc_issuer" {
  description = "The issuer whose tokens the launcher role accepts."
  type        = string
  default     = "https://oidc.hatchrun.io"
}

variable "oidc_provider_arn" {
  description = "ARN of an IAM OIDC provider for oidc_issuer that already exists in the account. An account has one provider per URL. Null creates it."
  type        = string
  default     = null
}

variable "role_name" {
  description = "Name of the launcher role. Null names it <name>-launcher."
  type        = string
  default     = null
}

variable "security_group_name" {
  description = "Name of the runner security group. Null names it <name>-runners."
  type        = string
  default     = null
}

variable "artifacts_bucket_name" {
  description = "Name of the artifacts and cache bucket. Null lets AWS pick a name starting with <name>-artifacts-."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size of each runner's root volume in GiB."
  type        = number
  default     = 30
}

variable "root_device_name" {
  description = "Device name of the runner root volume. It must match the root device of the AMI the runners boot."
  type        = string
  default     = "/dev/sda1"
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
