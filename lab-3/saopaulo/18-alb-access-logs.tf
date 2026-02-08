############################################
# Lab 3: São Paulo ALB Access Logs S3 Bucket
# Before terraform destroy: terraform state rm 'aws_s3_bucket.liberdade_alb_logs'
############################################

#-----------------------------------------------------------------------------
# S3 Bucket for ALB Access Logs
#-----------------------------------------------------------------------------

resource "aws_s3_bucket" "liberdade_alb_logs" {
  bucket = "liberdade-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.saopaulo_tags, {
    Name = "${local.saopaulo_prefix}-alb-logs"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "liberdade_alb_logs_pab" {
  bucket                  = aws_s3_bucket.liberdade_alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for audit trail
resource "aws_s3_bucket_versioning" "liberdade_alb_logs_versioning" {
  bucket = aws_s3_bucket.liberdade_alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "liberdade_alb_logs_sse" {
  bucket = aws_s3_bucket.liberdade_alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "liberdade_alb_logs_owner" {
  bucket = aws_s3_bucket.liberdade_alb_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

#-----------------------------------------------------------------------------
# Bucket Policy for ELB Access
#-----------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "liberdade_alb_logs_policy" {
  bucket = aws_s3_bucket.liberdade_alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.liberdade_alb_logs.arn,
          "${aws_s3_bucket.liberdade_alb_logs.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid    = "AllowELBRootAcl"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.elb_account_id_sa_east_1}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.liberdade_alb_logs.arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid    = "AllowELBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.liberdade_alb_logs.arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowELBLogDeliveryAcl"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.liberdade_alb_logs.arn
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.liberdade_alb_logs_pab]
}

#-----------------------------------------------------------------------------
# Lifecycle Rule - Auto-expire old logs
#-----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "liberdade_alb_logs_lifecycle" {
  bucket = aws_s3_bucket.liberdade_alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.alb_logs_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
