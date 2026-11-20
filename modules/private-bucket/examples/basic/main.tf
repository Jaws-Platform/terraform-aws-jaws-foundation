module "context" {
  source = "../../../context"

  name_root    = "acme"
  managed_by   = "acme-infra"
  owner        = "acme"
  organization = "acme"
  project      = "chess-bot"
  environment  = "prod"
  repository   = "acme/chess-bot"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "records" {
  source = "../../"

  name = "acme-chess-bot-records"
}

output "arn" {
  value = module.records.arn
}
