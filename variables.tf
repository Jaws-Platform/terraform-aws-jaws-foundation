variable "name_root" {
  description = "Prefix of every resource name, in kebab-case, for example `acme`. The state bucket is `<name_root>-tfstate` unless `state_bucket_name` is set, and `name_prefix` is `<name_root>-<project>-<environment>`."
  type        = string
}

variable "organization" {
  description = "Organization the account's projects belong to, in kebab-case. Becomes the `Organization` tag."
  type        = string
}

variable "project" {
  description = "Name of the project this stack is, in kebab-case, for example `infra`. Used in `name_prefix` and as the `Project` tag."
  type        = string
}

variable "environment" {
  description = "Deployment environment: one of `dev`, `staging`, `prod` or `preview`. Becomes the `Environment` tag."
  type        = string
}

variable "repository" {
  description = "GitHub repository that owns this stack, as `owner/repo`, for example `acme/infra`. Becomes the `Repository` tag."
  type        = string
}

variable "owner" {
  description = "GitHub user or team responsible for the stack. Becomes the `Owner` tag."
  type        = string
}

variable "managed_by" {
  description = "The tool that manages the resources, in kebab-case, for example `terraform`. Becomes the `ManagedBy` tag."
  type        = string
}

variable "extra_tags" {
  description = "Additional tags merged into `tags`. The six required keys (Organization, Project, Environment, Repository, ManagedBy, Owner) win on conflict."
  type        = map(string)
  default     = {}
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket. Null names it `<name_root>-tfstate`."
  type        = string
  default     = null
}

variable "state_admin_principal_arns" {
  description = "IAM principal ARNs exempt from every deny in the state bucket's policy except TLS, for example an administrator role and the role that applies this stack. Required when `state_prefix_access` is set, so that someone can always change the policy."
  type        = list(string)
  default     = []
}

variable "state_prefix_access" {
  description = "Hardens the state bucket's policy when set: a map of state key prefix to the principals that may `read` and `write` objects under it. Everyone else, including principals with `s3:*`, is denied object access. Leave empty for a TLS-only policy."
  type = map(object({
    read  = optional(list(string), [])
    write = optional(list(string), [])
  }))
  default = {}
}

variable "service_linked_roles" {
  description = "IAM service-linked roles to create, keyed by AWS service name, for example `{ \"spot.amazonaws.com\" = {} }` for the role EC2 needs before an account's first Spot launch. `description` should be the role's current description when you import one that already exists. An account holds one role per service, so list each service in one stack only."
  type = map(object({
    description = optional(string)
  }))
  default = {}
}
