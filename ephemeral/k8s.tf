resource "kubernetes_namespace" "workshop" {
  metadata {
    name   = var.kube_namespace
    labels = { "app.kubernetes.io/name" = var.project }
  }
}

resource "kubernetes_role" "service_deployer" {
  metadata {
    name      = "service-deployer"
    namespace = kubernetes_namespace.workshop.metadata[0].name
  }

  rule {
    api_groups = ["elbv2.k8s.aws"]
    resources  = ["targetgroupbindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "service_deployer" {
  metadata {
    name      = "service-deployer"
    namespace = kubernetes_namespace.workshop.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.service_deployer.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = local.service_deployer_group
    api_group = "rbac.authorization.k8s.io"
  }
}
