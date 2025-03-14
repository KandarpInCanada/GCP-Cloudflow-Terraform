# Create the Artifact Registry repository
resource "google_artifact_registry_repository" "myapp_repo" {
  provider      = google
  location      = "us-central1"
  repository_id = "myapp-repo"
  description   = "Artifact Registry for MyApp"
  format        = "DOCKER"

  lifecycle {
    prevent_destroy = true # Prevent accidental deletion of the repository
    ignore_changes = [
      description,
      labels,
    ]
  }
}
