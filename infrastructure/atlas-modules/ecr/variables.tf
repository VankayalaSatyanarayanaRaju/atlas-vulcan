variable "aws_region" {
  description = "AWS region for ECR repositories"
  type        = string
  default     = "us-east-1"
}


# ──────────────────────────────────────────────
# Repository Configuration
# ──────────────────────────────────────────────

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)

  default = [
    "scanning/trivy"
  ]
}

variable "image_tag_mutability" {
  description = "Tag mutability setting for the repositories"
  type        = string
  default     = "MUTABLE"

  validation {
    condition = contains(
      ["MUTABLE", "IMMUTABLE"],
      var.image_tag_mutability
    )

    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "name_tag" {
  description = "Value for the Name tag"
  type        = string
  default     = "infra-idv-ecr"
}

# ──────────────────────────────────────────────
# Optional Lifecycle Policies
# ──────────────────────────────────────────────

variable "lifecycle_policies" {
  description = "Map of repository name to lifecycle policy rules"

  type = map(object({
    rules = list(any)
  }))

  default = {}
}