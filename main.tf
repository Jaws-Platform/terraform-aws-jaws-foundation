# Root module: what a new AWS account needs before any stack can live in it.
#
#   context               the names and the tag set every stack shares (no resources)
#   tfstate-bucket        the bucket that holds every stack's Terraform state
#   service-linked-role   the service-linked roles the account needs up front
#
# It only wires the submodules together. Each can be used on its own, and each
# keeps its own input validation.

locals {
  state_bucket_name = coalesce(var.state_bucket_name, "${var.name_root}-tfstate")
}

module "context" {
  source = "./modules/context"

  name_root    = var.name_root
  organization = var.organization
  project      = var.project
  environment  = var.environment
  repository   = var.repository
  owner        = var.owner
  managed_by   = var.managed_by
  extra_tags   = var.extra_tags
}

module "state_bucket" {
  source = "./modules/tfstate-bucket"

  name                 = local.state_bucket_name
  admin_principal_arns = var.state_admin_principal_arns
  prefix_access        = var.state_prefix_access
}

module "service_linked_role" {
  source   = "./modules/service-linked-role"
  for_each = var.service_linked_roles

  aws_service_name = each.key
  description      = each.value.description
}
