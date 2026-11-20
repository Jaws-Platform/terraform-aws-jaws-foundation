output "tags" {
  description = "Tag map for a provider's `default_tags`: Organization, Project, Environment, Repository, ManagedBy and Owner, merged over `extra_tags`. Known at plan time."
  value       = module.context.tags
}

output "name_prefix" {
  description = "Resource name prefix for this stack: `<name_root>-<project>-<environment>`."
  value       = module.context.name_prefix
}

output "state_bucket_name" {
  description = "Name of the Terraform state bucket, for the `bucket` argument of an S3 backend."
  value       = module.state_bucket.name
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket, for the IAM policies of the roles that read and write state."
  value       = module.state_bucket.arn
}

output "service_linked_role_arns" {
  description = "ARN of each service-linked role, keyed by AWS service name."
  value       = { for service, role in module.service_linked_role : service => role.arn }
}
