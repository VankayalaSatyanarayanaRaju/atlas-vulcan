# ──────────────────────────────────────────────
# AWS Account Information
# ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────
# ECR Repositories
# ──────────────────────────────────────────────

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }


}

# ──────────────────────────────────────────────
# Repository Policy
# Grant account-level pull/push access
# ──────────────────────────────────────────────

resource "aws_ecr_repository_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowAccountAccess"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Lifecycle Policies
# ──────────────────────────────────────────────

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = {
    for name, repo in aws_ecr_repository.this : name => repo
    if lookup(var.lifecycle_policies, name, null) != null
  }

  repository = each.value.name

  policy = jsonencode({
    rules = var.lifecycle_policies[each.key].rules
  })
}