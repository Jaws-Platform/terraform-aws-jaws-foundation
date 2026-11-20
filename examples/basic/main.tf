# The tags come out of the module that also creates the state bucket. That is
# not a cycle: `tags` is derived from inputs alone, so the provider can be
# configured from it before any resource is planned.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.foundation.tags
  }
}

# The names and tags every stack in the account shares, the state bucket
# (`acme-tfstate`), and the service-linked role EC2 needs before the account's
# first Spot launch.
module "foundation" {
  source = "../../"

  name_root    = "acme"
  organization = "acme"
  project      = "infra"
  environment  = "prod"
  repository   = "acme/infra"
  owner        = "platform-team"
  managed_by   = "terraform"

  service_linked_roles = {
    "spot.amazonaws.com" = { description = "Default EC2 Spot Service Linked Role" }
  }
}

output "state_bucket_name" {
  description = "The `bucket` of every stack's S3 backend."
  value       = module.foundation.state_bucket_name
}

output "tags" {
  description = "The tag set, for other stacks' `default_tags`."
  value       = module.foundation.tags
}
