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

# Outputs
output "kubernetes_cluster_name" {
  value = google_container_cluster.primary.name
}

output "kubernetes_cluster_host" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}
