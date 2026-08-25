locals {
  default_raw = jsondecode(var.default_checks_json)
  service_raw = jsondecode(var.service_checks_json)

  skip_defaults              = try(local.service_raw["skip_defaults"], false)
  default_checks_for_service = local.skip_defaults ? [] : try(local.default_raw["default"], [])
  service_checks             = try(local.service_raw[var.service_name], [])

  service_check_keys = { for c in local.service_checks : c.key => true }
  filtered_defaults = [
    for c in local.default_checks_for_service : c
    if !lookup(local.service_check_keys, c.key, false)
  ]

  merged_checks = {
    (var.service_name) = concat(local.filtered_defaults, local.service_checks)
  }

  check_data = {
    for svc, checks in local.merged_checks :
    "${svc}.yaml" => join("\n", [
      for c in checks :
      trimspace(join("\n", compact([
        "- name: ${c.name}",
        "  key: ${c.key}",
        "  type: ${lookup(c, "type", "notEmpty")}",
        lookup(c, "expected", "") != "" ? "  expected: \"${c.expected}\"" : "",
      ])))
    ])
  }
}

resource "kubernetes_service_account_v1" "validator" {
  metadata {
    name      = "config-validator-${var.service_name}"
    namespace = var.namespace
    labels    = { app = "config-validator", service = var.service_name }
  }
}

resource "kubernetes_role_v1" "validator" {
  metadata {
    name      = "config-validator-${var.service_name}"
    namespace = var.namespace
    labels    = { app = "config-validator", service = var.service_name }
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "configmaps"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "validator" {
  metadata {
    name      = "config-validator-${var.service_name}"
    namespace = var.namespace
    labels    = { app = "config-validator", service = var.service_name }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.validator.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.validator.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_config_map_v1" "checks" {
  metadata {
    name      = "${var.name}-checks"
    namespace = var.namespace
    labels    = { app = "config-validator", service = var.service_name }
  }

  data = local.check_data
}

resource "kubernetes_config_map_v1" "script" {
  metadata {
    name      = "${var.name}-script"
    namespace = var.namespace
    labels    = { app = "config-validator", service = var.service_name }
  }

  data = {
    "validate.sh" = file("${path.module}/scripts/validate.sh")
  }
}

resource "kubernetes_job_v1" "validation" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = { app = "config-validator", service = var.service_name }
  }

  spec {
    ttl_seconds_after_finished = var.ttl_seconds_after_finished
    backoff_limit              = 0

    template {
      metadata {
        labels = { app = "config-validator", service = var.service_name }
        annotations = {
          "sumologic.com/sourceCategory"            = var.sourceCategory
          "sumologic.com/sourceCategoryReplaceDash" = "-"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.validator.metadata[0].name
        restart_policy       = "Never"

        security_context {
          run_as_non_root = true
          run_as_user     = var.run_as_user
        }

        container {
          name              = "verifier"
          image             = var.kubectl_image
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/sh", "/scripts/validate.sh"]

          security_context {
            run_as_non_root = true
            run_as_user     = var.run_as_user
          }

          resources {
            requests = {
              cpu    = var.resources_requests_cpu
              memory = var.resources_requests_memory
            }
            limits = {
              cpu    = var.resources_limits_cpu
              memory = var.resources_limits_memory
            }
          }

          env {
            name  = "NAMESPACE"
            value = var.namespace
          }

          env {
            name  = "CHECK_DIR"
            value = "/checks"
          }

          volume_mount {
            name       = "checks"
            mount_path = "/checks"
            read_only  = true
          }

          volume_mount {
            name       = "script"
            mount_path = "/scripts"
            read_only  = true
          }
        }

        volume {
          name = "checks"
          config_map {
            name = kubernetes_config_map_v1.checks.metadata[0].name
          }
        }

        volume {
          name = "script"
          config_map {
            name         = kubernetes_config_map_v1.script.metadata[0].name
            default_mode = "0755"
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = var.timeout
  }

  depends_on = [kubernetes_role_binding_v1.validator]
}
