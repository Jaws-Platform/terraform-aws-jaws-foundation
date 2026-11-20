# Basic: bootstrap an account

What a new AWS account needs before any other stack:

- the tag set and name prefix every stack shares, from `context`;
- the Terraform state bucket, `acme-tfstate`: versioned, encrypted, TLS only,
  with a policy that so far only refuses plain HTTP;
- the service-linked role EC2 needs before the account's first Spot launch.

The provider's `default_tags` come from the module's own `tags` output. That
is not a cycle: the tags are derived from inputs alone.

```sh
terraform init
terraform plan
```

This stack's own state cannot live in a bucket that does not exist yet. Apply
it once with local state, then add an S3 backend that points at the new
bucket and run `terraform init -migrate-state`.

In your own configuration, replace the relative `source` with the registry
address:

```hcl
module "foundation" {
  source  = "Jaws-Platform/jaws-foundation/aws"
  version = "0.1.0" # x-release-please-version

  name_root    = "acme"
  organization = "acme"
  project      = "infra"
  environment  = "prod"
  repository   = "acme/infra"
  owner        = "platform-team"
  managed_by   = "terraform"
}
```
