provider "kubernetes" {
  host                   = var.kubernetes_host
  client_certificate     = base64decode(var.kubernetes_client_certificate)
  client_key             = base64decode(var.kubernetes_client_key)
  cluster_ca_certificate = base64decode(var.kubernetes_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = var.kubernetes_host
    client_certificate     = base64decode(var.kubernetes_client_certificate)
    client_key             = base64decode(var.kubernetes_client_key)
    cluster_ca_certificate = base64decode(var.kubernetes_ca_certificate)
  }
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "age" {
  metadata {
    name      = "age"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  data = {
    "key.txt" = var.sops_age_key
  }
}

resource "kubernetes_secret_v1" "repo" {
  for_each = var.repositories

  metadata {
    name      = "repo-${each.key}"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = merge(
    {
      url  = each.value.url
      type = each.value.type
    },
    each.value.ssh_key != null ? { sshPrivateKey = each.value.ssh_key } : {},
    each.value.insecure ? { insecure = "true" } : {}
  )
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  values = [
    yamlencode(merge({
      server = {
        ingress = {
          enabled = true
        }
      }
      configs = {
        params = {
          "server.insecure" = true
        }
        cmp = {
          create = true
          plugins = {
            helmfile = {
              allowConcurrency = true
              generate = {
                command = ["bash", "-c", <<-EOF
                  if [[ -v ENV_NAME ]]; then
                    helmfile -n "$ARGOCD_APP_NAMESPACE" -e $ENV_NAME template --include-crds -q
                  elif [[ -v ARGOCD_ENV_ENV_NAME ]]; then
                    helmfile -n "$ARGOCD_APP_NAMESPACE" -e "$ARGOCD_ENV_ENV_NAME" template --include-crds -q
                  else
                    helmfile -n "$ARGOCD_APP_NAMESPACE" template --include-crds -q
                  fi
                EOF
                ]
              }
              lockRepo = false
            }
          }
        }
      }
      repoServer = {
        extraContainers = [
          {
            name    = "helmfile"
            image   = var.helmfile_image
            command = ["/var/run/argocd/argocd-cmp-server"]
            env = [
              { name = "SOPS_AGE_KEY_FILE", value = "/app/config/age/key.txt" },
              { name = "HELM_CACHE_HOME", value = "/tmp/helm/cache" },
              { name = "HELM_CONFIG_HOME", value = "/tmp/helm/config" },
              { name = "HELMFILE_CACHE_HOME", value = "/tmp/helmfile/cache" },
              { name = "HELMFILE_TEMPDIR", value = "/tmp/helmfile/tmp" },
            ]
            securityContext = {
              runAsNonRoot = true
              runAsUser    = 999
            }
            volumeMounts = [
              { mountPath = "/var/run/argocd", name = "var-files" },
              { mountPath = "/home/argocd/cmp-server/plugins", name = "plugins" },
              { mountPath = "/home/argocd/cmp-server/config/plugin.yaml", subPath = "helmfile.yaml", name = "argocd-cmp-cm" },
              { mountPath = "/tmp", name = "cmp-tmp" },
              { mountPath = "/app/config/age/", name = "age" },
            ]
          }
        ]
        volumes = [
          { name = "argocd-cmp-cm", configMap = { name = "argocd-cmp-cm" } },
          { name = "cmp-tmp", emptyDir = {} },
          { name = "age", secret = { secretName = "age" } },
        ]
      }
    }, var.values))
  ]

  depends_on = [kubernetes_secret_v1.age, kubernetes_secret_v1.repo]
}

resource "kubernetes_manifest" "root_app" {
  count = var.root_app != null && var.root_app.enabled ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "apps"
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.root_app.repo_url
        targetRevision = var.root_app.target_revision
        path           = var.root_app.path
        plugin = {
          name = "helmfile"
          env = [
            {
              name  = "ENV_NAME"
              value = var.root_app.env_name
            }
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "RespectIgnoreDifferences=true"
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
