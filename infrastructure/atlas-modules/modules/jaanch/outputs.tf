output "job_name" {
  description = "Name of the validation job"
  value       = kubernetes_job_v1.validation.metadata[0].name
}

output "check_count" {
  description = "Number of validation checks executed"
  value       = length(local.merged_checks[var.service_name])
}

output "service_account_name" {
  description = "Service account used by the validator"
  value       = kubernetes_service_account_v1.validator.metadata[0].name
}
