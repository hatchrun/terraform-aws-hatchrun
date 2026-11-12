# Artifacts of CI runs, one object each at
# artifacts/<days>d/<tenant>/<repository id>/<run id>/<random>, where
# <days> is the retention tier of the run: 30 or 90. hatchrun is the
# only reader and writer; runners get presigned URLs for single objects.
# The rules delete by tier prefix and drop uploads that never finished.
#
# The job cache lives here too, at cache/<tenant>/<repository id>/<random>.
# It has no expiry rule: S3 cannot expire by last use, and an object
# that goes before its row would make the entry hit and then fail to
# download. hatchrun's reconciler deletes entries not restored for 7
# days, object and row.
resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifacts_bucket_name
  bucket_prefix = var.artifacts_bucket_name == null ? "${var.name}-artifacts-" : null

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-artifacts-30d"
    status = "Enabled"

    filter {
      prefix = "artifacts/30d/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "expire-artifacts-90d"
    status = "Enabled"

    filter {
      prefix = "artifacts/90d/"
    }

    expiration {
      days = 90
    }
  }

  rule {
    id     = "abort-unfinished-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid       = "TlsOnly"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}
