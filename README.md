# terraform-aws-jaws-foundation

[![Terraform Registry](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fregistry.terraform.io%2Fv1%2Fmodules%2FJaws-Platform%2Fjaws-foundation%2Faws&query=%24.version&prefix=v&label=registry&logo=terraform&color=7B42BC)](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest)
[![GitHub release](https://img.shields.io/github/v/release/Jaws-Platform/terraform-aws-jaws-foundation?label=release)](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/releases/latest)
[![CI](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/actions/workflows/ci.yml/badge.svg?event=pull_request)](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/blob/main/LICENSE)

The things an AWS account needs before any Terraform stack can live in it:
one naming and tagging convention, a state bucket that only the right roles
can reach, hardened private buckets for data that must outlive a stack, the
service-linked roles AWS will not create for a least-privilege role, and
short-lived administrator access for a person, with no IAM user or access key.

It is one of the [Jaws](https://github.com/jwallace145/jaws) module families,
and has no dependency on Jaws: everything is a plain input.

## What it creates

```text
 ┌─ AWS account ──────────────────────────────────────────────────────────┐
 │                                                                        │
 │  context               names and tags, no resources                    │
 │    tags         ─────► every provider's default_tags                   │
 │    name_prefix  ─────► <name_root>-<project>-<environment>             │
 │                                                                        │
 │  tfstate-bucket        <name_root>-tfstate                             │
 │    project=<project>/env=<env>/<project>-<env>.tfstate   + .tflock     │
 │    versioned, encrypted, TLS only, never destroyed                     │
 │    optional policy: each key prefix readable and writable only by      │
 │    the roles you list                                                  │
 │                                                                        │
 │  service-linked-role   one per AWS service, for example EC2 Spot       │
 │                                                                        │
 │  private-bucket        durable project data, one per use               │
 │  identity-center-access   one person, one permission set, no keys      │
 └────────────────────────────────────────────────────────────────────────┘
```

The root module creates the first three in one call. `private-bucket` and
`identity-center-access` are used on their own, where they are needed.

## Modules

| Module | Creates |
|---|---|
| [root](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest) | An account's bootstrap in one call: `context`, `tfstate-bucket`, and a `service-linked-role` per listed service. |
| [`context`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/context) | Nothing. Derives the tag set (`Organization`, `Project`, `Environment`, `Repository`, `ManagedBy`, `Owner`) and the name prefix for a stack, known at plan time, for the provider's `default_tags`. |
| [`tfstate-bucket`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/tfstate-bucket) | The versioned, encrypted, TLS-only S3 bucket that holds every stack's state, locked with the native `.tflock` object. Its policy can confine each key prefix to the roles that plan and apply that stack. |
| [`private-bucket`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/private-bucket) | A versioned, encrypted, TLS-only, never-destroyed S3 bucket for data that must outlive the stack that writes it, with optional expiry for short-lived objects. |
| [`service-linked-role`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/service-linked-role) | One IAM service-linked role, such as `AWSServiceRoleForEC2Spot`, created up front so that a role without `iam:CreateServiceLinkedRole` can use the service. Never destroyed; an existing role is imported. |
| [`identity-center-access`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/identity-center-access) | One IAM Identity Center user with one permission set in one or more accounts: console and CLI access through `aws sso login`, with one-hour credentials and no IAM user. |

## Usage

Bootstrap an account. The tags come from the same module that creates the
state bucket; that is not a cycle, because `tags` is derived from inputs
alone:

```hcl
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.foundation.tags
  }
}

module "foundation" {
  source  = "Jaws-Platform/jaws-foundation/aws"
  version = "0.1.1" # x-release-please-version

  name_root    = "acme"
  organization = "acme"
  project      = "infra"
  environment  = "prod"
  repository   = "acme/infra"
  owner        = "platform-team"
  managed_by   = "terraform"

  # EC2 needs this role before the account's first Spot launch.
  service_linked_roles = {
    "spot.amazonaws.com" = { description = "Default EC2 Spot Service Linked Role" }
  }
}
```

Every other stack in the account then keeps its state in that bucket:

```hcl
terraform {
  backend "s3" {
    bucket       = "acme-tfstate"
    key          = "project=guitar/env=prod/guitar-prod.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

and tags its resources the same way, with `context` on its own:

```hcl
module "context" {
  source  = "Jaws-Platform/jaws-foundation/aws//modules/context"
  version = "0.1.1" # x-release-please-version

  name_root    = "acme"
  organization = "acme"
  project      = "guitar"
  environment  = "prod"
  repository   = "acme/guitar"
  owner        = "platform-team"
  managed_by   = "terraform"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}
```

## Examples

- [`basic`](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/tree/main/examples/basic):
  the tag set, the state bucket and the EC2 Spot service-linked role.
- [`hardened-state`](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/tree/main/examples/hardened-state):
  a state bucket whose policy gives each project's plan and apply roles their
  own key prefix and denies everyone else.

## Tagging

The modules in every Jaws family take no tag map. A resource gets `Component`
(and `Name`, where it has one) from the module that creates it, and every
other tag from the caller's provider `default_tags`, so a stack cannot forget
one. `context` is the one place those tags are defined:

| Tag | From |
|---|---|
| `Organization`, `Project`, `Environment`, `Repository`, `ManagedBy`, `Owner` | `context`, through the provider's `default_tags` |
| `Component`, `Name` | the module that creates the resource |

To report on cost by these tags, activate them as
[cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html)
in the Billing console once resources carry them.

## What to know before using it

- **The buckets and roles are never destroyed.** `tfstate-bucket`,
  `private-bucket`, `service-linked-role` and the Identity Center user and
  permission set carry `prevent_destroy`, which Terraform does not let an
  input switch off. To remove one on purpose, remove it from state first.
- **Import what already exists.** An account has one service-linked role per
  service; if AWS already created it, import it rather than creating a second.
- **A hardened state bucket needs an administrator.** With
  `state_prefix_access`, list the role that applies the bucket in
  `state_admin_principal_arns`, or its next apply cannot update the policy.
- **`identity-center-access` needs an organization instance** of IAM Identity
  Center, which can only be enabled in the console.
- **`us-east-1` is the region these were built and tested in.**
- **Providers are never configured here.** The caller configures `aws`.
- **No customer-managed KMS keys.** Buckets use SSE-S3 with a bucket key,
  which costs nothing.

## Development

See [CONTRIBUTING.md](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/blob/main/CONTRIBUTING.md)
for local setup, the commit and pull request rules, CI, and how releases work.
`scripts/check.sh` runs everything CI runs, with no AWS credentials.

## Root module reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| context | ./modules/context | n/a |
| service\_linked\_role | ./modules/service-linked-role | n/a |
| state\_bucket | ./modules/tfstate-bucket | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment: one of `dev`, `staging`, `prod` or `preview`. Becomes the `Environment` tag. | `string` | n/a | yes |
| managed\_by | The tool that manages the resources, in kebab-case, for example `terraform`. Becomes the `ManagedBy` tag. | `string` | n/a | yes |
| name\_root | Prefix of every resource name, in kebab-case, for example `acme`. The state bucket is `<name_root>-tfstate` unless `state_bucket_name` is set, and `name_prefix` is `<name_root>-<project>-<environment>`. | `string` | n/a | yes |
| organization | Organization the account's projects belong to, in kebab-case. Becomes the `Organization` tag. | `string` | n/a | yes |
| owner | GitHub user or team responsible for the stack. Becomes the `Owner` tag. | `string` | n/a | yes |
| project | Name of the project this stack is, in kebab-case, for example `infra`. Used in `name_prefix` and as the `Project` tag. | `string` | n/a | yes |
| repository | GitHub repository that owns this stack, as `owner/repo`, for example `acme/infra`. Becomes the `Repository` tag. | `string` | n/a | yes |
| extra\_tags | Additional tags merged into `tags`. The six required keys (Organization, Project, Environment, Repository, ManagedBy, Owner) win on conflict. | `map(string)` | `{}` | no |
| service\_linked\_roles | IAM service-linked roles to create, keyed by AWS service name, for example `{ "spot.amazonaws.com" = {} }` for the role EC2 needs before an account's first Spot launch. `description` should be the role's current description when you import one that already exists. An account holds one role per service, so list each service in one stack only. | <pre>map(object({<br/>    description = optional(string)<br/>  }))</pre> | `{}` | no |
| state\_admin\_principal\_arns | IAM principal ARNs exempt from every deny in the state bucket's policy except TLS, for example an administrator role and the role that applies this stack. Required when `state_prefix_access` is set, so that someone can always change the policy. | `list(string)` | `[]` | no |
| state\_bucket\_name | Name of the Terraform state bucket. Null names it `<name_root>-tfstate`. | `string` | `null` | no |
| state\_prefix\_access | Hardens the state bucket's policy when set: a map of state key prefix to the principals that may `read` and `write` objects under it. Everyone else, including principals with `s3:*`, is denied object access. Leave empty for a TLS-only policy. | <pre>map(object({<br/>    read  = optional(list(string), [])<br/>    write = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| name\_prefix | Resource name prefix for this stack: `<name_root>-<project>-<environment>`. |
| service\_linked\_role\_arns | ARN of each service-linked role, keyed by AWS service name. |
| state\_bucket\_arn | ARN of the Terraform state bucket, for the IAM policies of the roles that read and write state. |
| state\_bucket\_name | Name of the Terraform state bucket, for the `bucket` argument of an S3 backend. |
| tags | Tag map for a provider's `default_tags`: Organization, Project, Environment, Repository, ManagedBy and Owner, merged over `extra_tags`. Known at plan time. |
<!-- END_TF_DOCS -->

## License

[MIT](https://github.com/Jaws-Platform/terraform-aws-jaws-foundation/blob/main/LICENSE)
