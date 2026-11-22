resource "aws_s3_bucket" "this" {
  bucket = var.name

  tags = {
    Name      = var.name
    Component = var.component
  }

  # Hard-coded: lifecycle arguments cannot come from variables. The bucket
  # holds durable project data (game records that become training data), so
  # the module never allows it to be destroyed with the rest of a stack.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning keeps every overwritten object; old versions are a safety net,
  # not an archive.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # Short-lived data (for example the results of ephemeral tasks) can expire
  # on its own; the bucket itself is still never destroyed.
  dynamic "rule" {
    for_each = var.current_object_expiration_days == null ? [] : [var.current_object_expiration_days]

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {
        prefix = ""
      }

      expiration {
        days = rule.value
      }
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

locals {
  bucket_arn = aws_s3_bucket.this.arn
  hardened   = var.access != null

  admins  = local.hardened ? var.access.admin_principal_arns : []
  writers = local.hardened ? var.access.writers : {}
  readers = local.hardened ? var.access.readers : {}
  listers = local.hardened ? var.access.listers : []
  listed  = distinct(concat(local.admins, flatten(values(local.writers)), flatten(values(local.readers)), local.listers))

  # Object reads, and adding or overwriting an object (a writer's actions).
  read_actions  = ["s3:GetObject*", "s3:ListMultipartUploadParts"]
  write_actions = ["s3:PutObject*", "s3:AbortMultipartUpload"]

  # Removing, restoring or replicating an object: the admins' alone. Deleting
  # would end a version's life early, and S3 replication writes with its own
  # actions, which s3:PutObject* does not match.
  admin_object_actions = [
    "s3:DeleteObject*",
    "s3:RestoreObject",
    "s3:ReplicateObject",
    "s3:ReplicateDelete",
    "s3:ReplicateTags",
    "s3:ObjectOwnerOverrideToBucketOwner",
  ]

  # Bucket configuration, including the bucket policy itself. Without this,
  # any principal with s3:* could replace the policy and undo the rest.
  configuration_actions = [
    "s3:PutBucket*",
    "s3:DeleteBucket*",
    "s3:PutAccelerateConfiguration",
    "s3:PutAnalyticsConfiguration",
    "s3:PutEncryptionConfiguration",
    "s3:PutIntelligentTieringConfiguration",
    "s3:PutInventoryConfiguration",
    "s3:PutLifecycleConfiguration",
    "s3:PutMetricsConfiguration",
    "s3:PutReplicationConfiguration",
  ]

  insecure_transport = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Resource = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]
    Condition = {
      Bool = {
        "aws:SecureTransport" = "false"
      }
    }
  }

  # One fence per kind of access: outside every prefix of the kind, only the
  # admins; under each prefix, only its principals and the admins.
  fences = {
    for kind, spec in {
      Reads  = { actions = local.read_actions, prefixes = local.readers }
      Writes = { actions = local.write_actions, prefixes = local.writers }
      } : kind => concat(
      [
        merge(
          {
            Sid       = "Deny${kind}OutsidePrefixes"
            Effect    = "Deny"
            Principal = "*"
            Action    = spec.actions
            Condition = { ArnNotEquals = { "aws:PrincipalArn" = local.admins } }
          },
          # Every object while the kind names no prefix; else everything outside them.
          {
            for key, value in {
              Resource    = "${local.bucket_arn}/*"
              NotResource = [for p in sort(keys(spec.prefixes)) : "${local.bucket_arn}/${p}*"]
            } : key => value if(key == "Resource") == (length(spec.prefixes) == 0)
          },
        )
      ],
      [
        for i, p in sort(keys(spec.prefixes)) : {
          Sid       = "Deny${kind}UnderPrefix${i}"
          Effect    = "Deny"
          Principal = "*"
          Action    = spec.actions
          Resource  = "${local.bucket_arn}/${p}*"
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = distinct(concat(spec.prefixes[p], local.admins)) } }
        }
      ],
    )
  }

  hardened_statements = concat(
    [
      {
        Sid       = "DenyUnlistedListing"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:ListBucket*"
        Resource  = local.bucket_arn
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = local.listed } }
      },
    ],
    local.fences["Reads"],
    local.fences["Writes"],
    [
      {
        Sid       = "DenyDeletesAndReplication"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.admin_object_actions
        Resource  = "${local.bucket_arn}/*"
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = local.admins } }
      },
      {
        Sid       = "DenyUnmanagedConfiguration"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.configuration_actions
        Resource  = local.bucket_arn
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = local.admins } }
      },
    ],
  )

  bucket_policy = {
    Version   = "2012-10-17"
    Statement = concat([local.insecure_transport], [for st in local.hardened_statements : st if local.hardened])
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode(local.bucket_policy)

  # A bucket policy cannot be written while Block Public Access is still
  # being applied; order them explicitly.
  depends_on = [aws_s3_bucket_public_access_block.this]

  lifecycle {
    precondition {
      condition     = length(jsonencode(local.bucket_policy)) <= 20480
      error_message = "the bucket policy exceeds S3's 20 KB limit; name fewer prefixes or principals in access."
    }
  }
}
