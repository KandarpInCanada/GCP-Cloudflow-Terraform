provider "google" {
  project     = var.project_id
  region      = "us-central1"
  zone        = "us-central1-a"
  credentials = file(var.gcp_credentials)
}

# Get Google Cloud configuration
data "google_client_config" "default" {}
