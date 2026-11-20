mock_provider "aws" {
  override_during = plan

  # The bucket's ID is its name; a mocked provider would otherwise invent one.
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::acme-tfstate"
      id  = "acme-tfstate"
    }
  }

  mock_resource "aws_iam_service_linked_role" {
    defaults = {
      arn  = "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
      name = "AWSServiceRoleForEC2Spot"
    }
  }
}

variables {
  name_root    = "acme"
  organization = "acme"
  project      = "infra"
  environment  = "prod"
  repository   = "acme/infra"
  owner        = "platform-team"
  managed_by   = "terraform"
}

run "names_and_tags_come_from_the_context" {
  command = plan

  assert {
    condition = tomap(output.tags) == tomap({
      Organization = "acme"
      Project      = "infra"
      Environment  = "prod"
      Repository   = "acme/infra"
      ManagedBy    = "terraform"
      Owner        = "platform-team"
    })
    error_message = "tags must be the six required tags"
  }

  assert {
    condition     = output.name_prefix == "acme-infra-prod"
    error_message = "name_prefix must be <name_root>-<project>-<environment>"
  }
}

run "the_state_bucket_is_named_after_name_root" {
  command = plan

  assert {
    condition     = local.state_bucket_name == "acme-tfstate"
    error_message = "the state bucket must default to <name_root>-tfstate"
  }

  assert {
    condition     = output.state_bucket_name == module.state_bucket.name && output.state_bucket_arn == module.state_bucket.arn
    error_message = "the state bucket outputs must be the tfstate-bucket module's outputs"
  }

  assert {
    condition     = length(module.service_linked_role) == 0 && output.service_linked_role_arns == {}
    error_message = "no service-linked role may be created by default"
  }
}

run "the_state_bucket_name_can_be_set" {
  command = plan

  variables {
    state_bucket_name = "acme-terraform-state-us-east-1"
  }

  assert {
    condition     = local.state_bucket_name == "acme-terraform-state-us-east-1"
    error_message = "state_bucket_name must override the derived name"
  }
}

run "extra_tags_never_override_the_required_tags" {
  command = plan

  variables {
    extra_tags = {
      CostCenter = "platform"
      Project    = "something-else"
    }
  }

  assert {
    condition     = output.tags["CostCenter"] == "platform" && output.tags["Project"] == "infra"
    error_message = "extra_tags must be merged in, and the required tags must win"
  }
}

run "a_hardened_state_bucket_policy" {
  command = plan

  variables {
    state_admin_principal_arns = ["arn:aws:iam::123456789012:role/acme-infra-ci-apply"]
    state_prefix_access = {
      "project=infra/" = {
        read  = ["arn:aws:iam::123456789012:role/acme-infra-ci-plan"]
        write = ["arn:aws:iam::123456789012:role/acme-infra-ci-apply"]
      }
    }
  }

  assert {
    condition     = local.state_bucket_name == "acme-tfstate" && output.state_bucket_arn == "arn:aws:s3:::acme-tfstate"
    error_message = "a hardened policy must not change which bucket is created"
  }
}

run "one_service_linked_role_per_service" {
  command = plan

  variables {
    service_linked_roles = {
      "spot.amazonaws.com" = { description = "Default EC2 Spot Service Linked Role" }
    }
  }

  assert {
    condition     = keys(output.service_linked_role_arns) == ["spot.amazonaws.com"]
    error_message = "service_linked_role_arns must be keyed by AWS service name"
  }

  assert {
    condition     = output.service_linked_role_arns["spot.amazonaws.com"] == "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
    error_message = "each entry must be the service-linked-role module's arn"
  }
}
