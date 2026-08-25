# ──────────────────────────────────────────────
# ECR Module Outputs
# ──────────────────────────────────────────────

output "registry_id" {
  description = "The ECR registry ID (AWS account ID)"
  value       = data.aws_caller_identity.current.account_id
}

output "repository_urls" {
  description = "Map of repository name to repository URL"
  value = {
    for name, repo in aws_ecr_repository.this : name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository name to repository ARN"
  value = {
    for name, repo in aws_ecr_repository.this : name => repo.arn
  }
}