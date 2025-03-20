provider "google" {
  project     = var.project_id
  region      = "us-central1"
  zone        = "us-central1-a"
  credentials = file(var.gcp_credentials)
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
  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_config,
    ]
  }
}

# Create node pool with improved resources
resource "google_container_node_pool" "primary_nodes" {
  name       = "myapp-node-pool"
  location   = "us-central1-a"
  cluster    = google_container_cluster.primary.name
  node_count = 1
  node_config {
    preemptible  = true
    machine_type = "e2-medium"
    disk_size_gb = 40
    disk_type    = "pd-standard"
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
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  lifecycle {
    ignore_changes = [
      node_count,
      node_config.0.labels,
      initial_node_count,
    ]
  }
}

# Output the GKE cluster details
output "kubernetes_cluster_name" {
  value = google_container_cluster.primary.name
}
output "kubernetes_cluster_host" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}
