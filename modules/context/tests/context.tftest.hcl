mock_provider "aws" {}

variables {
  project      = "guitar"
  environment  = "prod"
  repository   = "example-org/guitar"
  name_root    = "acme-technologies"
  managed_by   = "acme-technologies-infra"
  owner        = "example-org"
  organization = "acme-technologies"
}

run "derives_names" {
  command = plan

  assert {
    condition     = output.name_prefix == "acme-technologies-guitar-prod"
    error_message = "name_prefix should be acme-technologies-<project>-<environment>, got ${output.name_prefix}"
  }

  assert {
    condition     = output.bucket_name == "acme-technologies-guitar"
    error_message = "bucket_name should be acme-technologies-<project>, got ${output.bucket_name}"
  }
}

run "emits_required_tags" {
  command = plan

  assert {
    condition = output.tags == {
      Organization = "acme-technologies"
      Project      = "guitar"
      Environment  = "prod"
      Repository   = "example-org/guitar"
      ManagedBy    = "acme-technologies-infra"
      Owner        = "example-org"
    }
    error_message = "tags should contain exactly the six required keys with default owner/organization"
  }
}

run "required_tags_win_over_extra_tags" {
  command = plan

  variables {
    extra_tags = {
      Project    = "not-guitar"
      ManagedBy  = "hand"
      CostCenter = "personal"
    }
  }

  assert {
    condition     = output.tags["Project"] == "guitar" && output.tags["ManagedBy"] == "acme-technologies-infra"
    error_message = "required tags must override conflicting extra_tags"
  }

  assert {
    condition     = output.tags["CostCenter"] == "personal"
    error_message = "non-conflicting extra_tags must be preserved"
  }
}

run "honours_owner_and_organization_overrides" {
  command = plan

  variables {
    owner        = "someone-else"
    organization = "other-org"
    environment  = "preview"
  }

  assert {
    condition     = output.tags["Owner"] == "someone-else" && output.tags["Organization"] == "other-org"
    error_message = "owner and organization inputs should flow into tags"
  }

  assert {
    condition     = output.name_prefix == "acme-technologies-guitar-preview"
    error_message = "name_prefix must keep its name_root regardless of the organization tag"
  }
}

run "names_follow_name_root" {
  command = plan

  variables {
    name_root = "jaws"
  }

  assert {
    condition     = output.name_prefix == "jaws-guitar-prod"
    error_message = "name_prefix should be <name_root>-<project>-<environment>, got ${output.name_prefix}"
  }

  assert {
    condition     = output.bucket_name == "jaws-guitar"
    error_message = "bucket_name should be <name_root>-<project>, got ${output.bucket_name}"
  }

  assert {
    condition     = output.tags["Organization"] == "acme-technologies"
    error_message = "name_root must not change the Organization tag, which has its own input"
  }
}

run "managed_by_sets_the_tag_and_still_wins_over_extra_tags" {
  command = plan

  variables {
    managed_by = "jaws"
    extra_tags = {
      ManagedBy = "hand"
    }
  }

  assert {
    condition     = output.tags["ManagedBy"] == "jaws"
    error_message = "managed_by should be the ManagedBy tag, over any extra_tags value"
  }
}

run "rejects_non_kebab_name_root" {
  command = plan

  variables {
    name_root = "Jaws_"
  }

  expect_failures = [var.name_root]
}

run "rejects_non_kebab_project" {
  command = plan

  variables {
    project = "Guitar_Site"
  }

  expect_failures = [var.project]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_malformed_repository" {
  command = plan

  variables {
    repository = "guitar"
  }

  expect_failures = [var.repository]
}

# The Organization tag names the GitHub organization or user that owns the
# project's repository, and ManagedBy may be any casing, such as JAWS. Neither
# is part of a name, so neither needs kebab-case.
run "accepts_a_github_owner_and_an_uppercase_managed_by" {
  command = plan

  variables {
    organization = "Braveheart-Chess"
    managed_by   = "JAWS"
  }

  assert {
    condition     = output.tags["Organization"] == "Braveheart-Chess" && output.tags["ManagedBy"] == "JAWS"
    error_message = "a GitHub owner and an uppercase ManagedBy must flow into the tags as given"
  }

  assert {
    condition     = output.name_prefix == "acme-technologies-guitar-prod"
    error_message = "names keep their name_root whatever the Organization tag says"
  }
}

run "rejects_an_organization_that_is_not_a_github_owner" {
  command = plan

  variables {
    organization = "Braveheart Chess"
  }

  expect_failures = [var.organization]
}

run "rejects_a_managed_by_with_spaces" {
  command = plan

  variables {
    managed_by = "managed by jaws"
  }

  expect_failures = [var.managed_by]
}
