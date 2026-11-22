# context

Part of [`Jaws-Platform/jaws-foundation/aws`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest) · [Registry](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/context) · [Source](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/tree/main/modules/context)

Derives the naming and tagging conventions for a project.
This module **creates no resources**, so all of its outputs are known at plan
time and can be fed into the AWS provider's `default_tags`.

## Usage

```hcl
module "context" {
  source  = "Jaws-Platform/jaws-foundation/aws//modules/context"
  version = "0.1.3" # x-release-please-version

  name_root    = "acme"
  managed_by   = "acme-infra"
  owner        = "acme"
  organization = "acme"
  project      = "guitar"
  environment  = "prod"
  repository   = "acme/guitar"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}
```

Pass `module.context.tags` to `default_tags` in every stack. Modules in the
Jaws families take no tag map, so this is the only place these tags are set,
and several policies in [`ci-policies`](https://registry.terraform.io/modules/Jaws-Platform/jaws-ci/aws/latest/submodules/ci-policies) scope a CI role's permissions by
the `Project` tag (CloudFront, ACM and EC2 among them): a resource without it
is out of that role's reach.

No input has an organisation-specific default. `name_root` and `organization`
are separate on purpose: one names resources, the other is a tag value, and
an account that changes its naming can keep its tags.

## Conventions

| Output | Value |
|---|---|
| `tags` | `Organization`, `Project`, `Environment`, `Repository`, `ManagedBy` (`managed_by`), `Owner`, merged over `extra_tags`. Required keys win any conflict. |
| `name_prefix` | `<name_root>-<project>-<environment>` |
| `bucket_name` | `<name_root>-<project>` |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment. One of `dev`, `staging`, `prod` or `preview`. | `string` | n/a | yes |
| managed\_by | Value of the `ManagedBy` tag: the tool that manages the project's resources. | `string` | n/a | yes |
| name\_root | Prefix of every resource name, in kebab-case: `name_prefix` is `<name_root>-<project>-<environment>` and `bucket_name` is `<name_root>-<project>`. Independent of the `organization` tag value. | `string` | n/a | yes |
| organization | Organization the project belongs to. Becomes the `Organization` tag. | `string` | n/a | yes |
| owner | GitHub user responsible for the project. Becomes the `Owner` tag. | `string` | n/a | yes |
| project | Project name in kebab-case, for example `guitar`. Used in resource names and the `Project` tag. | `string` | n/a | yes |
| repository | GitHub repository that owns the project, as `owner/repo` (for example `acme/guitar`). | `string` | n/a | yes |
| extra\_tags | Additional tags merged into `tags`. The required keys (Organization, Project, Environment, Repository, ManagedBy, Owner) always win on conflict. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | Site bucket name for the project: `<name_root>-<project>`. Shared by every environment of the project. |
| name\_prefix | Resource name prefix: `<name_root>-<project>-<environment>`. |
| tags | Tag map for the caller's provider `default_tags`: Organization, Project, Environment, Repository, ManagedBy and Owner, merged over `extra_tags` (required keys win). |
<!-- END_TF_DOCS -->
