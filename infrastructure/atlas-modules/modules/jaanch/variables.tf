variable "name" {
  description = "Name of the validation job and related resources"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where the service is deployed"
  type        = string
}

variable "service_name" {
  description = "Service being validated (used as pod label selector: app=<service_name>)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "dmaInstallId" {
  description = "DMA install ID for EKS cluster lookup (cluster name = dma-<dmaInstallId>)"
  type        = string
}

variable "default_checks_json" {
  description = "Content of default-checks.json (pre-rendered with template vars by the caller)"
  type        = string
}

variable "service_checks_json" {
  description = "Content of service-specific checks JSON (optional)"
  type        = string
  default     = "{}"
}

variable "kubectl_image" {
  description = "kubectl container image for the verifier job"
  type        = string
  default     = "bitnami/kubectl:1.31.0"
}

variable "run_as_user" {
  description = "UID to run the verifier container as (non-root)"
  type        = number
  default     = 1000
}

variable "resources_requests_cpu" {
  description = "CPU request for the verifier container"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for the verifier container"
  type        = string
  default     = "128Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit for the verifier container"
  type        = string
  default     = "500m"
}

variable "resources_limits_memory" {
  description = "Memory limit for the verifier container"
  type        = string
  default     = "256Mi"
}

variable "timeout" {
  description = "Job timeout"
  type        = string
  default     = "10m"
}

variable "ttl_seconds_after_finished" {
  description = "TTL for completed jobs before auto-cleanup"
  type        = number
  default     = 600
}

variable "sourceCategory" {
  description = "Sumo Logic source category for the validation job logs"
  type        = string
  default     = ""
}