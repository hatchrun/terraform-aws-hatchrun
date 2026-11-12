# What hatchrun may do in this account: launch the runner images from
# the template into this VPC and end the instances it tagged. There is
# no iam:PassRole, so no instance can get a role. hatchrun signs a
# short-lived token with subject tenant:<tenant> and trades it for the
# role's credentials through the account's IAM provider for the issuer.

locals {
  issuer_host       = trimprefix(var.oidc_issuer, "https://")
  oidc_provider_arn = var.oidc_provider_arn != null ? var.oidc_provider_arn : aws_iam_openid_connect_provider.hatchrun[0].arn
  launch_template   = aws_launch_template.runner.arn
}

resource "aws_iam_openid_connect_provider" "hatchrun" {
  count = var.oidc_provider_arn == null ? 1 : 0

  url            = var.oidc_issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = var.tags
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = ["tenant:${var.tenant}"]
    }
  }
}

resource "aws_iam_role" "launcher" {
  name                 = coalesce(var.role_name, "${var.name}-launcher")
  description          = "hatchrun-ci launches and removes CI runner instances"
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.trust.json

  tags = var.tags
}

data "aws_iam_policy_document" "launcher" {
  # EC2 allows describing only on "*".
  statement {
    effect = "Allow"
    sid    = "List"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    sid       = "LaunchInstances"
    actions   = ["ec2:RunInstances"]
    resources = ["${local.arn}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/hatchrun:tenant"
      values   = [var.tenant]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:LaunchTemplate"
      values   = [local.launch_template]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:MetadataHttpTokens"
      values   = ["required"]
    }

    condition {
      test     = "NumericLessThanEquals"
      variable = "ec2:MetadataHttpPutResponseHopLimit"
      values   = ["1"]
    }
  }

  statement {
    effect    = "Allow"
    sid       = "LaunchVolumes"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["${local.arn}:volume/*"]

    condition {
      test     = "Bool"
      variable = "ec2:Encrypted"
      values   = ["true"]
    }
  }

  # The runner images, built in this account.
  statement {
    effect  = "Allow"
    sid     = "LaunchOwnImages"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "${local.arn}:image/*",
      "arn:${local.partition}:ec2:${local.region}::image/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:Owner"
      values   = [local.account]
    }
  }

  statement {
    effect  = "Allow"
    sid     = "LaunchNetwork"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "${local.arn}:subnet/*",
      "${local.arn}:network-interface/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:Vpc"
      values   = ["${local.arn}:vpc/${aws_vpc.this.id}"]
    }
  }

  statement {
    effect  = "Allow"
    sid     = "LaunchFromTemplate"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      local.launch_template,
      "${local.arn}:security-group/${aws_security_group.runners.id}",
      "${local.arn}:spot-instances-request/*",
    ]
  }

  # Each launch is an instant EC2 Fleet of one. The instance it starts
  # is held to LaunchInstances.
  statement {
    effect    = "Allow"
    sid       = "LaunchFleet"
    actions   = ["ec2:CreateFleet"]
    resources = ["${local.arn}:fleet/*"]
  }

  # A fleet takes no user data or instance tags of its own, so each
  # launch adds a version of the template with them and deletes it
  # after.
  statement {
    effect = "Allow"
    sid    = "RunnerTemplateVersions"
    actions = [
      "ec2:CreateLaunchTemplateVersion",
      "ec2:DeleteLaunchTemplateVersions",
    ]
    resources = [local.launch_template]
  }

  statement {
    effect  = "Allow"
    sid     = "TagAtLaunch"
    actions = ["ec2:CreateTags"]
    resources = [
      "${local.arn}:instance/*",
      "${local.arn}:volume/*",
      "${local.arn}:spot-instances-request/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet"]
    }
  }

  # Artifacts: hatchrun presigns single-object calls for runners with
  # this role's credentials, so the URLs can do no more than this.
  statement {
    effect = "Allow"
    sid    = "ArtifactObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/artifacts/*"]
  }

  # The job cache: the same calls on cache/ objects (HeadObject reads
  # the size of a saved entry and needs GetObject), and the reconciler's
  # deletes of evicted entries.
  statement {
    effect = "Allow"
    sid    = "CacheObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/cache/*"]
  }

  # Ending a job's instance, turning its metadata off, and starting a
  # pool instance a job took.
  statement {
    effect = "Allow"
    sid    = "ManageOwnInstances"
    actions = [
      "ec2:TerminateInstances",
      "ec2:ModifyInstanceMetadataOptions",
      "ec2:StartInstances",
    ]
    resources = ["${local.arn}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/hatchrun:tenant"
      values   = [var.tenant]
    }
  }

  # The warm pool: stopping a warmed-up instance and setting the user
  # data of a job's instance, only while the instance still carries its
  # pool tag. A job's instance has none.
  statement {
    effect    = "Allow"
    sid       = "ManagePoolInstances"
    actions   = ["ec2:StopInstances", "ec2:ModifyInstanceAttribute"]
    resources = ["${local.arn}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/hatchrun:tenant"
      values   = [var.tenant]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/hatchrun:pool"
      values   = ["false"]
    }
  }

  # A pool instance gets its job's tags while it has its pool tag. The
  # pool tag itself can never be set, so a job's instance cannot become
  # a pool instance. ForAllValues is true for an empty key list, so the
  # keys must exist.
  statement {
    effect    = "Allow"
    sid       = "TagPoolInstances"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.arn}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/hatchrun:tenant"
      values   = [var.tenant]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/hatchrun:pool"
      values   = ["false"]
    }

    condition {
      test     = "Null"
      variable = "aws:TagKeys"
      values   = ["false"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Name", "hatchrun:job-id", "hatchrun:runner-name"]
    }
  }

  # The pool tag is deleted when a job takes the instance, and nothing
  # else is.
  statement {
    effect    = "Allow"
    sid       = "UntagPoolInstances"
    actions   = ["ec2:DeleteTags"]
    resources = ["${local.arn}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/hatchrun:tenant"
      values   = [var.tenant]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/hatchrun:pool"
      values   = ["false"]
    }

    condition {
      test     = "Null"
      variable = "aws:TagKeys"
      values   = ["false"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["hatchrun:pool"]
    }
  }

  # Creating a launch template version can carry an instance profile
  # into a fleet without iam:PassRole, so launches with any profile
  # are refused. hatchrun only creates instant fleets, which launch at
  # once under this policy. A maintain or request fleet relaunches later
  # through the EC2 Fleet service-linked role without asking this policy
  # again; this role cannot create that service-linked role, and no
  # condition key limits CreateFleet to the instant type. See the
  # README's security notes.
  statement {
    effect  = "Deny"
    sid     = "NoInstanceProfile"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "${local.arn}:instance/*",
    ]

    condition {
      test     = "Null"
      variable = "ec2:InstanceProfile"
      values   = ["false"]
    }
  }
}

resource "aws_iam_role_policy" "launcher" {
  name   = "run-ci-jobs"
  role   = aws_iam_role.launcher.id
  policy = data.aws_iam_policy_document.launcher.json
}
