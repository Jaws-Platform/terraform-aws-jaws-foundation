provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.foundation.tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # The roles that plan and apply each stack. They do not have to exist yet:
  # the bucket policy matches them by ARN, in a condition.
  role = {
    infra_plan   = "arn:aws:iam::${local.account_id}:role/acme-infra-ci-plan"
    infra_apply  = "arn:aws:iam::${local.account_id}:role/acme-infra-ci-apply"
    guitar_plan  = "arn:aws:iam::${local.account_id}:role/acme-guitar-ci-plan"
    guitar_apply = "arn:aws:iam::${local.account_id}:role/acme-guitar-ci-apply"
  }
}

# A state bucket whose own policy decides who can reach each stack's state, so
# a principal with `s3:*` elsewhere in the account still cannot read or
# overwrite it. Each project gets one key prefix: its plan role may read under
# it (and write only `.tflock` objects), its apply role may write.
module "foundation" {
  source = "../../"

  name_root    = "acme"
  organization = "acme"
  project      = "infra"
  environment  = "prod"
  repository   = "acme/infra"
  owner        = "platform-team"
  managed_by   = "terraform"

  # Exempt from the denies, so the policy can always be changed: the role that
  # applies this stack. Being listed grants nothing by itself.
  state_admin_principal_arns = [local.role.infra_apply]

  state_prefix_access = {
    "project=infra/" = {
      read  = [local.role.infra_plan]
      write = [local.role.infra_apply]
    }
    "project=guitar/" = {
      read  = [local.role.guitar_plan]
      write = [local.role.guitar_apply]
    }
  }
}

output "state_bucket_name" {
  description = "The `bucket` of every stack's S3 backend."
  value       = module.foundation.state_bucket_name
}
