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
