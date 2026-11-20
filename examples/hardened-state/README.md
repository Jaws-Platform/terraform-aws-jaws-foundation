# Hardened state: one key prefix per project

IAM policies on a CI role bound only that role. Any other principal in the
account with broad S3 permissions can still read, overwrite or delete every
stack's state. This example closes that from the bucket's side:

- each project's state lives under `project=<name>/`;
- that project's plan role may read under its prefix, and write nothing but
  `.tflock` objects, so `terraform plan` can lock but never write state;
- its apply role may write there;
- everyone else is denied, whatever their IAM policies say;
- the role that applies this stack is listed as an administrator, so the
  policy can always be changed.

Every statement the policy adds is a `Deny`, so being listed grants nothing:
each role still needs an IAM policy that allows the action. The roles do not
have to exist when the bucket is created, because the policy matches them by
ARN in a condition.

```sh
terraform init
terraform plan
```

In your own configuration, replace the relative `source` with the registry
address:

```hcl
module "foundation" {
  source  = "jaws-platform/jaws-foundation/aws"
  version = "0.1.0" # x-release-please-version

  # ... names and tags as in the basic example ...

  state_admin_principal_arns = [local.role.infra_apply]

  state_prefix_access = {
    "project=guitar/" = {
      read  = [local.role.guitar_plan]
      write = [local.role.guitar_apply]
    }
  }
}
```

The [`ci-plan-role` and `ci-apply-role`](https://registry.terraform.io/modules/jaws-platform/jaws-ci/aws/latest)
modules create roles with matching `tfstate/read` and `tfstate/write`
policies.
