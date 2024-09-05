variable outer_project_id {}
variable inner_project_id {}

# Enable necessary API Services for the Outer Loop
resource "google_project_service" "outer_project_services" {
  project = var.outer_project_id
  service = "artifactregistry.googleapis.com"
}

resource "google_project_service" "outer_project_services_tpu" {
  project = var.outer_project_id
  service = "tpu.googleapis.com"
}

resource "google_project_service" "outer_project_services_cloudbuild" {
  project = var.outer_project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "outer_project_services_servicenetworking" {
  project = var.outer_project_id
  service = "servicenetworking.googleapis.com"
}

resource "google_project_service" "outer_project_services_cloudresourcemanager" {
  project = var.outer_project_id
  service = "cloudresourcemanager.googleapis.com"
}

# Enable necessary API Services for the Inner Loop
resource "google_project_service" "inner_project_services" {
  project = var.inner_project_id
  service = "artifactregistry.googleapis.com"
}

resource "google_project_service" "inner_project_services_cloudbuild" {
  project = var.inner_project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "inner_project_services_tpu" {
  project = var.inner_project_id
  service = "tpu.googleapis.com"
}

resource "google_project_service" "inner_project_services_cloudresourcemanager" {
  project = var.inner_project_id
  service = "cloudresourcemanager.googleapis.com"
}

output "result" {
  value = "force modules to depend on api enablement"
}