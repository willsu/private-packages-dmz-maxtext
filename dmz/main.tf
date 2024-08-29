variable outer_project_id {}
variable inner_project_id {}
variable inner_loop_cloud_build_agent_email {}
variable api_enablement_result {}

# Create the DMZ service account
resource "google_service_account" "dmz_service_account" {
  account_id   = "cloud-build-agent-dmz"
  display_name = "Cloud Build Agent DMZ"
  project      = var.outer_project_id 
  disabled     = false
}

# Grant IAM Permissions for DMZ Service Account
resource "google_project_iam_member" "dmz_service_account_artifact_registry_admin" {
  project = var.outer_project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

resource "google_project_iam_member" "dmz_service_account_storage_object_user" {
  project = var.outer_project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

resource "google_project_iam_member" "dmz_service_account_storage_admin" {
  project = var.outer_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

resource "google_project_iam_member" "dmz_service_account_logging_log_writer" {
  project = var.outer_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

# Grant IAM Permissions for DMZ Service Account in Inner Loop
resource "google_project_iam_member" "dmz_service_account_inner_loop_artifact_registry_admin" {
  project = var.inner_project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

resource "google_project_iam_member" "dmz_service_account_inner_loop_cloud_build_builder" {
  project = var.inner_project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

resource "google_project_iam_member" "dmz_service_account_inner_loop_storage_admin" {
  project = var.inner_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

# Grant the DMZ service account access to the Inner Loop service account
resource "google_service_account_iam_member" "dmz_service_account_inner_loop_cloud_build_agent_editor" {
  service_account_id = "projects/${var.inner_project_id}/serviceAccounts/${var.inner_loop_cloud_build_agent_email}"
  #service_account_id = google_service_account.inner_loop_cloud_build_agent.email 
  role                = "roles/editor"
  member              = "serviceAccount:${google_service_account.dmz_service_account.email}"
}

output "result" {
  value = "finished"
}
