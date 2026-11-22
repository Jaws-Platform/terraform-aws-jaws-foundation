# private-bucket

Part of [`Jaws-Platform/jaws-foundation/aws`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest) · [Registry](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/private-bucket) · [Source](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/tree/main/modules/private-bucket)

A private S3 bucket for durable project data that must outlive the stack
that produces it, such as the game records a bot writes. Versioned,
SSE-S3 encrypted with a bucket key, Block Public Access on,
`BucketOwnerEnforced`, and a TLS-only bucket policy, or a hardened one. Noncurrent object
versions expire after `noncurrent_version_expiration_days` (30 by default)
and incomplete multipart uploads are aborted after 7 days.

**Short-lived data.** Set `current_object_expiration_days` to expire current
objects too, for data that is copied elsewhere at once, such as the outputs of
ephemeral tasks. Old versions still expire after
`noncurrent_version_expiration_days`.

`prevent_destroy` is hard-coded: a `terraform destroy` of the stack keeps
the bucket and its objects, by design. Who may read and write the objects is
decided by the callers' IAM policies; the bucket policy grants nothing. Set
`access` to bound them as well ([Hardened bucket policy](#hardened-bucket-policy)).

The bucket carries `Name` and `Component` tags; every other tag comes
from the caller's provider `default_tags`.

## Usage

```hcl
module "records" {
  source  = "Jaws-Platform/jaws-foundation/aws//modules/private-bucket"
  version = "0.2.0" # x-release-please-version

  name = "acme-chess-bot-records"
}
```

## Hardened bucket policy

Without `access` the policy only requires TLS, and anyone in the account whose
IAM allows S3 can read, overwrite or delete the objects. With it, the policy
also names who may reach the bucket at all:

```hcl
module "records" {
  source  = "Jaws-Platform/jaws-foundation/aws//modules/private-bucket"
  version = "0.2.0" # x-release-please-version

  name = "acme-chess-bot-records"

  access = {
    # Anything, the bucket's configuration and policy included: the owner's
    # break-glass principals and the role that applies this bucket.
    admin_principal_arns = [
      "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_0123456789abcdef",
      "arn:aws:iam::123456789012:root",
      "arn:aws:iam::123456789012:role/acme-chess-bot-ci-apply",
    ]
    writers = { "records/" = [module.bot.role_arn] } # adds under records/; never reads or deletes
    readers = {}                                     # only the admins read
    # Lists without reading: the plan role, whose refresh calls HeadBucket,
    # which S3 authorizes as s3:ListBucket.
    listers = ["arn:aws:iam::123456789012:role/acme-chess-bot-ci-plan"]
  }
}
```

Every statement is a `Deny` for `Principal = "*"` matched on `aws:PrincipalArn`
(exact ARNs: a wildcard is refused), so it grants nothing; a principal still
needs an IAM policy that allows the action:

| Statement | Denies |
|---|---|
| `DenyInsecureTransport` | Any request without TLS |
| `DenyUnlistedListing` | `s3:ListBucket*`, and so `HeadBucket`, to anyone not in `access` (the role that plans the bucket goes in `listers`) |
| `DenyReadsOutsidePrefixes` | Object reads outside every `readers` prefix (every object, with no readers) to anyone but the admins |
| `DenyReadsUnderPrefix<N>` | Object reads under `readers` prefix `N` to anyone but its readers and the admins |
| `DenyWritesOutsidePrefixes` | Adding or overwriting objects outside every `writers` prefix to anyone but the admins |
| `DenyWritesUnderPrefix<N>` | Adding or overwriting objects under `writers` prefix `N` to anyone but its writers and the admins |
| `DenyDeletesAndReplication` | Deleting, restoring or replicating any object to anyone but the admins |
| `DenyUnmanagedConfiguration` | Bucket configuration changes, the bucket policy included, to anyone but the admins |

A writer adds and overwrites objects (`s3:PutObject*`,
`s3:AbortMultipartUpload`); overwritten versions stay recoverable until
`noncurrent_version_expiration_days`. Only the admins delete, restore or
replicate objects (`s3:DeleteObject*`, `s3:RestoreObject`, and S3
replication's own write actions, `s3:ReplicateObject`, `s3:ReplicateDelete`,
`s3:ReplicateTags` and `s3:ObjectOwnerOverrideToBucketOwner`, which
`s3:PutObject*` does not match). List the role that applies this bucket in
`admin_principal_arns`, or its next apply cannot update the policy. The account
root user is denied too, unless listed, but can always delete a bucket policy
as a last resort.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the bucket, for example `acme-chess-bot-records`. Also the value of its `Name` tag. | `string` | n/a | yes |
| access | Who may reach the bucket's objects and change its configuration. `null` keeps the<br/>policy to the TLS rule. With it, every statement is a deny matched on<br/>`aws:PrincipalArn` (exact ARNs, no wildcards), so it bounds what IAM allows and<br/>grants nothing:<br/><br/>- `admin_principal_arns`: may do anything, the bucket's configuration and policy<br/>  included. List the owner's break-glass principals and the role that applies<br/>  this bucket, or its next apply cannot update the policy.<br/>- `writers`: prefix => principals that may add or overwrite objects under that<br/>  prefix (`""` is the whole bucket). Writers do not read, and only the admins<br/>  delete, restore or replicate objects.<br/>- `readers`: prefix => principals that may read objects under that prefix.<br/>- `listers`: principals that may list the bucket, and so check it exists<br/>  (`HeadBucket` is authorized as `s3:ListBucket`), without reading or writing<br/>  objects: the role that plans this bucket, whose refresh calls `HeadBucket`.<br/><br/>Anyone in `access` may list the bucket; nobody else may. A prefix is `""` or ends in<br/>`/`, and no two prefixes of one map overlap. | <pre>object({<br/>    admin_principal_arns = list(string)<br/>    writers              = optional(map(list(string)), {})<br/>    readers              = optional(map(list(string)), {})<br/>    listers              = optional(list(string), [])<br/>  })</pre> | `null` | no |
| component | Value of the `Component` tag on the bucket. | `string` | `"private-bucket"` | no |
| current\_object\_expiration\_days | Expire current objects this many days after they are written, for short-lived data such as task results. `null` keeps them forever. | `number` | `null` | no |
| noncurrent\_version\_expiration\_days | Overwritten and deleted object versions are kept this many days before they expire. | `number` | `30` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the bucket, for IAM policies. |
| name | Name of the bucket, for `aws s3 sync` targets and IAM policies. |
<!-- END_TF_DOCS -->
