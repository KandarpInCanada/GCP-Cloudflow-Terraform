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

  # Ignore changes if the resource already exists
  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_config,
    ]
  }
}
