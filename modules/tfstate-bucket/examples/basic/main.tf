module "context" {
  source = "../../../context"

  name_root    = "acme"
  managed_by   = "acme-infra"
  owner        = "acme"
  organization = "acme"
  project      = "infra"
  environment  = "prod"
  repository   = "acme/acme-infra"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "state_bucket" {
  source = "../../"

  name = "acme-tfstate"
}

output "state_bucket_name" {
  value = module.state_bucket.name
}

output "state_bucket_arn" {
  value = module.state_bucket.arn
}
