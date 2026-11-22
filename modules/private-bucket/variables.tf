variable "name" {
  description = "Name of the bucket, for example `acme-chess-bot-records`. Also the value of its `Name` tag."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name)) &&
      !can(regex("\\.\\.", var.name)) &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.name))
    )
    error_message = "name must be a valid S3 bucket name: 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit, without consecutive dots, and not an IP address."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Overwritten and deleted object versions are kept this many days before they expire."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a positive integer."
  }
}

variable "current_object_expiration_days" {
  description = "Expire current objects this many days after they are written, for short-lived data such as task results. `null` keeps them forever."
  type        = number
  default     = null

  validation {
    condition     = var.current_object_expiration_days == null || (try(var.current_object_expiration_days >= 1, false) && try(floor(var.current_object_expiration_days) == var.current_object_expiration_days, false))
    error_message = "current_object_expiration_days must be a positive integer or null."
  }
}

variable "component" {
  description = "Value of the `Component` tag on the bucket."
  type        = string
  default     = "private-bucket"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}

variable "access" {
  description = <<-EOT
    Who may reach the bucket's objects and change its configuration. `null` keeps the
    policy to the TLS rule. With it, every statement is a deny matched on
    `aws:PrincipalArn` (exact ARNs, no wildcards), so it bounds what IAM allows and
    grants nothing:

    - `admin_principal_arns`: may do anything, the bucket's configuration and policy
      included. List the owner's break-glass principals and the role that applies
      this bucket, or its next apply cannot update the policy.
    - `writers`: prefix => principals that may add or overwrite objects under that
      prefix (`""` is the whole bucket). Writers do not read, and only the admins
      delete, restore or replicate objects.
    - `readers`: prefix => principals that may read objects under that prefix.
    - `listers`: principals that may list the bucket, and so check it exists
      (`HeadBucket` is authorized as `s3:ListBucket`), without reading or writing
      objects: the role that plans this bucket, whose refresh calls `HeadBucket`.

    Anyone in `access` may list the bucket; nobody else may. A prefix is `""` or ends in
    `/`, and no two prefixes of one map overlap.
  EOT
  type = object({
    admin_principal_arns = list(string)
    writers              = optional(map(list(string)), {})
    readers              = optional(map(list(string)), {})
    listers              = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.access == null || length(try(var.access.admin_principal_arns, [])) > 0
    error_message = "access.admin_principal_arns must name at least one principal, or no one could ever change the bucket policy."
  }

  validation {
    condition = var.access == null || alltrue([
      for arn in concat(
        try(var.access.admin_principal_arns, []),
        flatten(values(try(var.access.writers, {}))),
        flatten(values(try(var.access.readers, {}))),
        try(var.access.listers, []),
      ) : can(regex("^arn:aws:(iam|sts)::[0-9]{12}:[^*?]+$", arn))
    ])
    error_message = "Every access principal must be a full IAM or STS ARN without wildcards: aws:PrincipalArn is matched exactly."
  }

  validation {
    condition = var.access == null || alltrue([
      for prefix in concat(keys(try(var.access.writers, {})), keys(try(var.access.readers, {}))) :
      prefix == "" || can(regex("^[A-Za-z0-9!_.*'()=-]+(/[A-Za-z0-9!_.*'()=-]+)*/$", prefix))
    ])
    error_message = "Every access prefix must be \"\" (the whole bucket) or a key prefix ending in /, such as records/."
  }

  validation {
    condition = var.access == null || alltrue(flatten([
      for map in [try(var.access.writers, {}), try(var.access.readers, {})] : [
        for a in keys(map) : [for b in keys(map) : a == b || !startswith(b, a)]
      ]
    ]))
    error_message = "Two prefixes of access.writers, or of access.readers, overlap: one would bypass the other's principals."
  }
}
