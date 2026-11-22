mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::acme-technologies-rusty-chess-records"
    }
  }
}

variables {
  name = "acme-technologies-rusty-chess-records"
}

run "bucket_hardening" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "acme-technologies-rusty-chess-records"
    error_message = "bucket name must be var.name"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be enabled"
  }

  assert {
    condition = (
      tolist(aws_s3_bucket_server_side_encryption_configuration.this.rule)[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      tolist(aws_s3_bucket_server_side_encryption_configuration.this.rule)[0].bucket_key_enabled == true
    )
    error_message = "objects must be encrypted with SSE-S3 and a bucket key"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "all four public access blocks must be on"
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "object ownership must be BucketOwnerEnforced"
  }

  assert {
    condition     = aws_s3_bucket.this.tags == tomap({ Name = "acme-technologies-rusty-chess-records", Component = "private-bucket" })
    error_message = "the bucket must carry Name and Component tags only"
  }
}

run "lifecycle_defaults" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "expire-noncurrent-versions" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30 &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].filter[0].prefix == ""
    )
    error_message = "rule 0 must expire noncurrent versions after 30 days by default, for every key"
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[1].id == "abort-incomplete-multipart-uploads" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].abort_incomplete_multipart_upload[0].days_after_initiation == 7 &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].filter[0].prefix == ""
    )
    error_message = "rule 1 must abort incomplete multipart uploads after 7 days, for every key"
  }
}

run "lifecycle_custom" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 90
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "noncurrent expiry must come from the variable"
  }
}

run "tls_only_policy" {
  command = plan

  assert {
    condition = (
      length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1 &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "the bucket policy must be exactly the TLS-only deny"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.name == "acme-technologies-rusty-chess-records" &&
      output.arn == "arn:aws:s3:::acme-technologies-rusty-chess-records"
    )
    error_message = "outputs must describe the bucket"
  }
}

run "rejects_bad_name" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

run "rejects_zero_days" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

# Short-lived data (task results) expires on its own.
run "expires_current_objects" {
  command = plan

  variables {
    current_object_expiration_days = 7
  }

  assert {
    condition = length([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r
      if r.id == "expire-current-objects" && r.status == "Enabled" && r.expiration[0].days == 7 && r.filter[0].prefix == ""
    ]) == 1
    error_message = "current objects expire after current_object_expiration_days"
  }
}

run "keeps_current_objects_by_default" {
  command = plan

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "expire-current-objects"]) == 0
    error_message = "current objects are kept unless an expiry is set"
  }
}

run "rejects_zero_current_expiry" {
  command = plan

  variables {
    current_object_expiration_days = 0
  }

  expect_failures = [var.current_object_expiration_days]
}

# A bot's records bucket: the bot writes under records/, and only the admins
# read, list beyond it or change the bucket.
run "access_writer_only" {
  command = plan

  variables {
    access = {
      admin_principal_arns = [
        "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_0123456789abcdef",
        "arn:aws:iam::123456789012:root",
        "arn:aws:iam::123456789012:role/acme-rusty-chess-ci-apply",
      ]
      writers = {
        "records/" = ["arn:aws:iam::123456789012:role/acme-rusty-chess-bot"]
      }
      listers = ["arn:aws:iam::123456789012:role/acme-rusty-chess-ci-plan"]
    }
  }

  assert {
    condition = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == [
      "DenyInsecureTransport",
      "DenyUnlistedListing",
      "DenyReadsOutsidePrefixes",
      "DenyWritesOutsidePrefixes",
      "DenyWritesUnderPrefix0",
      "DenyDeletesAndReplication",
      "DenyUnmanagedConfiguration",
    ]
    error_message = "the hardened policy must contain exactly the documented statements, in order"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Effect == "Deny" && s.Principal == "*"])
    error_message = "every statement must be a deny for every principal: the policy bounds IAM and grants nothing"
  }

  assert {
    condition = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyUnlistedListing"][0].Condition.ArnNotEquals["aws:PrincipalArn"] == [
      "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_0123456789abcdef",
      "arn:aws:iam::123456789012:root",
      "arn:aws:iam::123456789012:role/acme-rusty-chess-ci-apply",
      "arn:aws:iam::123456789012:role/acme-rusty-chess-bot",
      "arn:aws:iam::123456789012:role/acme-rusty-chess-ci-plan",
    ]
    error_message = "everyone in access, and nobody else, may list the bucket: the plan role's refresh calls HeadBucket"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyReadsOutsidePrefixes"][0].Resource == "arn:aws:s3:::acme-technologies-rusty-chess-records/*" &&
      jsonencode([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyReadsOutsidePrefixes"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode(var.access.admin_principal_arns)
    )
    error_message = "with no readers, only the admins may read any object: a writer does not read"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyWritesOutsidePrefixes"][0].NotResource == ["arn:aws:s3:::acme-technologies-rusty-chess-records/records/*"] &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyWritesUnderPrefix0"][0].Resource == "arn:aws:s3:::acme-technologies-rusty-chess-records/records/*" &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyWritesUnderPrefix0"][0].Condition.ArnNotEquals["aws:PrincipalArn"][0] == "arn:aws:iam::123456789012:role/acme-rusty-chess-bot"
    )
    error_message = "the writer may write under records/ only, and the admins anywhere"
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyWritesUnderPrefix0"][0].Action == ["s3:PutObject*", "s3:AbortMultipartUpload"]
    error_message = "a writer adds and overwrites objects, and nothing else"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyDeletesAndReplication"][0].Resource == "arn:aws:s3:::acme-technologies-rusty-chess-records/*" &&
      jsonencode([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyDeletesAndReplication"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode(var.access.admin_principal_arns) &&
      alltrue([
        for action in ["s3:DeleteObject*", "s3:RestoreObject", "s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags", "s3:ObjectOwnerOverrideToBucketOwner"] :
        contains([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyDeletesAndReplication"][0].Action, action)
      ])
    )
    error_message = "only the admins delete, restore or replicate objects: a writer cannot end a version's life, and replication's own actions are fenced"
  }

  assert {
    condition = (
      contains([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyUnmanagedConfiguration"][0].Action, "s3:PutBucket*") &&
      jsonencode([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyUnmanagedConfiguration"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode(var.access.admin_principal_arns)
    )
    error_message = "only the admins may change the bucket's configuration, its policy included"
  }
}

run "access_with_readers" {
  command = plan

  variables {
    access = {
      admin_principal_arns = ["arn:aws:iam::123456789012:root"]
      writers              = { "records/" = ["arn:aws:iam::123456789012:role/writer"] }
      readers              = { "records/" = ["arn:aws:iam::123456789012:role/reader"] }
    }
  }

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyReadsOutsidePrefixes"][0].NotResource == ["arn:aws:s3:::acme-technologies-rusty-chess-records/records/*"] &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyReadsUnderPrefix0"][0].Condition.ArnNotEquals["aws:PrincipalArn"] == [
        "arn:aws:iam::123456789012:role/reader",
        "arn:aws:iam::123456789012:root",
      ]
    )
    error_message = "a reader may read under its prefix only"
  }
}

run "rejects_a_wildcard_principal" {
  command = plan

  variables {
    access = {
      admin_principal_arns = ["arn:aws:iam::123456789012:role/acme-*"]
    }
  }

  expect_failures = [var.access]
}

run "rejects_a_prefix_without_a_slash" {
  command = plan

  variables {
    access = {
      admin_principal_arns = ["arn:aws:iam::123456789012:root"]
      writers              = { "records" = ["arn:aws:iam::123456789012:role/writer"] }
    }
  }

  expect_failures = [var.access]
}

run "rejects_overlapping_prefixes" {
  command = plan

  variables {
    access = {
      admin_principal_arns = ["arn:aws:iam::123456789012:root"]
      writers = {
        "records/"     = ["arn:aws:iam::123456789012:role/writer"]
        "records/pgn/" = ["arn:aws:iam::123456789012:role/other"]
      }
    }
  }

  expect_failures = [var.access]
}

run "rejects_access_without_admins" {
  command = plan

  variables {
    access = {
      admin_principal_arns = []
    }
  }

  expect_failures = [var.access]
}
