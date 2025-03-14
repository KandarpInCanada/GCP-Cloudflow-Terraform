# Check if the repository already exists
data "google_artifact_registry_repository" "existing_repo" {
  provider      = google
  location      = "us-central1"
  repository_id = "myapp-repo"
}

# Create the repository only if it doesn't exist
resource "google_artifact_registry_repository" "myapp_repo" {
  provider      = google
  location      = "us-central1"
  repository_id = "myapp-repo"
  description   = "Artifact Registry for MyApp"
  format        = "DOCKER"

  lifecycle {
    prevent_destroy = true
  }

  count = length(data.google_artifact_registry_repository.existing_repo.id) == 0 ? 1 : 0
}
