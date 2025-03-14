provider "google" {
  project     = var.project_id
  region      = "us-central1"
  zone        = "us-central1-a"
  credentials = file(var.gcp_credentials)
}

variable "project_id" {
  default = "spry-gateway-453614-i1"
}

variable "gcp_credentials" {
  default = "/home/runner/gcp-sa-key.json"
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# Get Google Cloud configuration
data "google_client_config" "default" {}

# Create GKE cluster
resource "google_container_cluster" "primary" {
  name                     = "myapp-gke-cluster"
  location                 = "us-central1-a"
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  # Add maintenance window to avoid unexpected disruptions
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00" # UTC time for maintenance (low traffic hours)
    }
  }
}

# Create node pool with improved resources
resource "google_container_node_pool" "primary_nodes" {
  name       = "myapp-node-pool"
  location   = "us-central1-a"
  cluster    = google_container_cluster.primary.name
  node_count = 2 # Increased to 2 for better availability

  node_config {
    preemptible  = true        # Keep preemptible for cost savings but be aware of potential disruptions
    machine_type = "e2-medium" # Upgraded from e2-small for more resources
    disk_size_gb = 40          # Increased from 10GB to resolve disk pressure
    disk_type    = "pd-standard"

    # Add labels for better node management
    labels = {
      environment = "production"
      app         = "myapp"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  # Add auto-scaling capability
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  # Add management settings for better operations
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Create a dependency to ensure Kubernetes resources wait for the cluster
resource "null_resource" "cluster_setup_dependency" {
  depends_on = [
    google_container_node_pool.primary_nodes
  ]
}

# Create namespace
resource "kubernetes_namespace" "myapp_namespace" {
  depends_on = [null_resource.cluster_setup_dependency]

  metadata {
    name = "myapp-namespace"
    labels = {
      name = "myapp"
    }
  }
}

# Install NFS server provisioner using Helm
resource "helm_release" "nfs_server_provisioner" {
  depends_on = [kubernetes_namespace.myapp_namespace]

  name       = "nfs-server-provisioner"
  repository = "https://charts.helm.sh/stable"
  chart      = "nfs-server-provisioner"
  namespace  = kubernetes_namespace.myapp_namespace.metadata[0].name

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = "5Gi" # Size of the backing PVC for the NFS server
  }

  set {
    name  = "storageClass.name"
    value = "nfs-client"
  }

  set {
    name  = "storageClass.defaultClass"
    value = "false"
  }

  set {
    name  = "storageClass.allowVolumeExpansion"
    value = "true"
  }

  set {
    name  = "storageClass.reclaimPolicy"
    value = "Retain"
  }
}

# Create standard storage class for other volumes
resource "kubernetes_storage_class" "standard_sc" {
  depends_on = [null_resource.cluster_setup_dependency]

  metadata {
    name = "standard-storage"
  }
  storage_provisioner = "pd.csi.storage.gke.io"
  parameters = {
    type = "pd-standard"
  }
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true
}

# Create persistent volume claim with ReadWriteMany using NFS
resource "kubernetes_persistent_volume_claim" "validator_pvc" {
  depends_on = [helm_release.nfs_server_provisioner]

  metadata {
    name      = "validator-storage-pvc"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "nfs-client"
  }
}

# Create config map for validator-api to access processor-api internally
resource "kubernetes_config_map" "myapp_config" {
  depends_on = [kubernetes_namespace.myapp_namespace]

  metadata {
    name      = "myapp-config"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
  }

  data = {
    PROCESSOR_API_BASE_URL = "http://processor-api-service.myapp-namespace.svc.cluster.local:6001" # Use full DNS for better resolution
    VOLUME_MOUNT_PATH      = "/data"
    LOG_LEVEL              = "info"
  }
}

# Create validator API deployment
resource "kubernetes_deployment" "validator_api" {
  depends_on = [kubernetes_persistent_volume_claim.validator_pvc]

  metadata {
    name      = "validator-api"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
    labels = {
      app = "validator-api"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "validator-api"
      }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "25%"
        max_unavailable = "25%"
      }
    }
    template {
      metadata {
        labels = {
          app = "validator-api"
        }
      }
      spec {
        container {
          name  = "validator-api"
          image = "us-central1-docker.pkg.dev/spry-gateway-453614-i1/cloud/validator-api:1.0.3"
          port {
            container_port = 6000
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map.myapp_config.metadata[0].name
            }
          }
          volume_mount {
            name       = "validator-storage"
            mount_path = "/data"
          }
          resources {
            requests = {
              memory            = "256Mi" # Increased from 128Mi
              cpu               = "150m"  # Increased from 100m
              ephemeral-storage = "1Gi"   # Added explicit storage request
            }
            limits = {
              memory            = "512Mi" # Increased from 256Mi
              cpu               = "300m"  # Increased from 200m
              ephemeral-storage = "2Gi"   # Added explicit storage limit
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 6000
            }
            initial_delay_seconds = 60 # Increased from 30
            period_seconds        = 15 # Increased from 10
            timeout_seconds       = 5  # Added timeout
            failure_threshold     = 3  # Added failure threshold
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 6000
            }
            initial_delay_seconds = 10 # Increased from 5
            period_seconds        = 10 # Increased from 5
            timeout_seconds       = 3  # Added timeout
            success_threshold     = 1  # Added success threshold
          }
        }
        volume {
          name = "validator-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.validator_pvc.metadata[0].name
          }
        }
        # Add tolerations to manage pods on preemptible nodes
        toleration {
          key      = "cloud.google.com/gke-preemptible"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }
}

# Create processor API deployment
resource "kubernetes_deployment" "processor_api" {
  depends_on = [kubernetes_persistent_volume_claim.validator_pvc]

  metadata {
    name      = "processor-api"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
    labels = {
      app = "processor-api"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "processor-api"
      }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "25%"
        max_unavailable = "25%"
      }
    }
    template {
      metadata {
        labels = {
          app = "processor-api"
        }
      }
      spec {
        container {
          name  = "processor-api"
          image = "us-central1-docker.pkg.dev/spry-gateway-453614-i1/cloud/processor-api:1.0.6"
          port {
            container_port = 6001
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map.myapp_config.metadata[0].name
            }
          }
          volume_mount {
            name       = "validator-storage"
            mount_path = "/data"
          }
          resources {
            requests = {
              memory            = "256Mi" # Increased from 128Mi
              cpu               = "150m"  # Increased from 100m
              ephemeral-storage = "1Gi"   # Added explicit storage request
            }
            limits = {
              memory            = "512Mi" # Increased from 256Mi
              cpu               = "300m"  # Increased from 200m
              ephemeral-storage = "2Gi"   # Added explicit storage limit
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 6001
            }
            initial_delay_seconds = 60 # Increased from 30
            period_seconds        = 15 # Increased from 10
            timeout_seconds       = 5  # Added timeout
            failure_threshold     = 3  # Added failure threshold
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 6001
            }
            initial_delay_seconds = 10 # Increased from 5
            period_seconds        = 10 # Increased from 5
            timeout_seconds       = 3  # Added timeout
            success_threshold     = 1  # Added success threshold
          }
        }
        volume {
          name = "validator-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.validator_pvc.metadata[0].name
          }
        }
        # Add tolerations to manage pods on preemptible nodes
        toleration {
          key      = "cloud.google.com/gke-preemptible"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }
}

resource "kubernetes_service" "validator_api_service" {
  metadata {
    name      = "validator-api-service"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
  }
  spec {
    selector = { app = "validator-api" }
    port {
      name        = "http"
      port        = 6000
      target_port = 6000
      node_port   = 31000 # Manually specify a NodePort (range: 30000-32767)
    }
    type = "NodePort" # Changed from ClusterIP to NodePort
  }
}

resource "kubernetes_service" "processor_api_service" {
  metadata {
    name      = "processor-api-service"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
  }
  spec {
    selector = { app = "processor-api" }
    port {
      name        = "http"
      port        = 6001
      target_port = 6001
      node_port   = 31001 # Manually specify a NodePort
    }
    type = "NodePort" # Changed from ClusterIP to NodePort
  }
}

resource "kubernetes_ingress_v1" "myapp_ingress" {
  depends_on = [kubernetes_service.validator_api_service]

  metadata {
    name      = "myapp-ingress"
    namespace = kubernetes_namespace.myapp_namespace.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/store-file"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.validator_api_service.metadata[0].name
              port { number = 6000 }
            }
          }
        }
        path {
          path      = "/calculate"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.validator_api_service.metadata[0].name
              port { number = 6000 }
            }
          }
        }
        path {
          path      = "/health"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.validator_api_service.metadata[0].name
              port { number = 6000 }
            }
          }
        }
      }
    }
  }
}

# Outputs
output "kubernetes_cluster_name" {
  value = google_container_cluster.primary.name
}

output "kubernetes_cluster_host" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}

output "validator_service_url" {
  value = "https://${try(kubernetes_ingress_v1.myapp_ingress.status[0].load_balancer[0].ingress[0].ip, "Pending")}/validator"
}

output "processor_service_url" {
  value = "https://${try(kubernetes_ingress_v1.myapp_ingress.status[0].load_balancer[0].ingress[0].ip, "Pending")}/processor"
}
