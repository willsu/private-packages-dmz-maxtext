variable inner_project_id {}
variable region {}
variable apt_inner_repo {}
variable pip_inner_repo {}
variable bucket_suffix {}
variable api_enablement_result {}

resource "google_service_account" "inner_loop_cloud_build_agent" {
  account_id   = "cloud-build-agent-inner-loop"
  display_name = "Cloud Build Agent Inner Loop"
  project      = var.inner_project_id
  disabled     = false
}

# Enable necessary API Services for the Inner Loop
resource "google_service_account" "inner_loop_tpu_service_account" {
  account_id   = "tpu-service-account-inner-loop"
  display_name = "TPU Service Account Inner Loop"
  project      = var.inner_project_id
  disabled     = false
}

# Grant IAM Permissions for Inner Loop Service Accounts
resource "google_project_iam_member" "inner_loop_cloud_build_agent_roles" {
  project = var.inner_project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.inner_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "inner_loop_cloud_build_agent_tpu_admin" {
  project = var.inner_project_id
  role    = "roles/tpu.admin"
  member  = "serviceAccount:${google_service_account.inner_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "inner_loop_cloud_build_agent_service_account_user" {
  project = var.inner_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.inner_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "inner_loop_cloud_build_agent_compute_admin" {
  project = var.inner_project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.inner_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "inner_loop_cloud_build_agent_iap" {
  project = var.inner_project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.inner_loop_cloud_build_agent.email}"
}
resource "google_project_iam_member" "inner_loop_cloud_build_agent_logging_log_writer" {
  project = var.inner_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.inner_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "inner_loop_tpu_service_account_storage_admin" {
  project = var.inner_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.inner_loop_tpu_service_account.email}"
}
resource "google_project_iam_member" "inner_loop_tpu_service_account_logging_log_writer" {
  project = var.inner_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.inner_loop_tpu_service_account.email}"
}

resource "google_project_iam_member" "inner_loop_tpu_service_account_monitoring_metric_writer" {
  project = var.inner_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.inner_loop_tpu_service_account.email}"
}
resource "google_project_iam_member" "inner_loop_tpu_service_account_tpu_viewer" {
  project = var.inner_project_id
  role    = "roles/tpu.viewer"
  member  = "serviceAccount:${google_service_account.inner_loop_tpu_service_account.email}"
}

resource "google_project_iam_member" "inner_loop_tpu_service_account_artifact_registry_reader" {
  project = var.inner_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.inner_loop_tpu_service_account.email}"
}

# Inner Loop Artifact Registry Repositories
resource "google_artifact_registry_repository" "inner_loop_apt_repo" {
  format = "apt"
  location = var.region
  repository_id = var.apt_inner_repo
  project = var.inner_project_id
  description = "Apt Package for Inner Loop"
}

resource "google_artifact_registry_repository" "inner_loop_pip_repo" {
  format = "python"
  location = var.region
  repository_id = var.pip_inner_repo
  project = var.inner_project_id
  description = "Python Package for Inner Loop"
}

# Inner Loop Storage Buckets
resource "google_storage_bucket" "inner_loop_artifacts_bucket" {
  name     = "maxtext-artifacts-inner-${var.bucket_suffix}"
  location = var.region
  force_destroy = true
  project     = var.inner_project_id
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "inner_loop_tests_bucket" {
  name     = "maxtext-tests-${var.bucket_suffix}"
  location = var.region
  force_destroy = true
  project     = var.inner_project_id
  uniform_bucket_level_access = true
}

# Inner Loop Network Components
resource "google_compute_network" "inner_loop_network" {
  name     = "vpc-inner-loop"
  auto_create_subnetworks = false
  project = var.inner_project_id
  routing_mode = "REGIONAL"
}

resource "google_compute_subnetwork" "inner_loop_subnet" {
  name      = "subnet-inner-loop"
  ip_cidr_range = "10.0.1.0/24"
  project  = var.inner_project_id
  region   = var.region
  network  = google_compute_network.inner_loop_network.self_link
  private_ip_google_access = true
}

resource "google_compute_firewall" "inner_loop_allow_inbound_from_gcp" {
  name     = "inner-loop-allow-inbound-from-gcp"
  project  = var.inner_project_id
  network  = google_compute_network.inner_loop_network.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["http-server", "https-server"]
  priority = 1000
}

resource "google_dns_managed_zone" "inner_loop_managed_zone" {
  name     = "googleapis-com"
  dns_name = "googleapis.com."
  project = var.inner_project_id
  visibility = "private"
  description = "Google APIs"

  private_visibility_config {
    networks {
      network_url = google_compute_network.inner_loop_network.self_link
    }
  }
}

resource "google_dns_record_set" "inner_loop_cname_record" {
  name   = "*.googleapis.com."
  rrdatas = ["googleapis.com."]
  type   = "CNAME"
  ttl    = 300
  managed_zone = google_dns_managed_zone.inner_loop_managed_zone.name
  project = var.inner_project_id
}

resource "google_dns_record_set" "inner_loop_a_record" {
  name   = "googleapis.com."
  rrdatas = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
  type   = "A"
  ttl    = 300
  managed_zone = google_dns_managed_zone.inner_loop_managed_zone.name
  project = var.inner_project_id
}

output "cloud_build_agent_email" {
  value = google_service_account.inner_loop_cloud_build_agent.email
}

output "artifacts_bucket_url" {
  value = google_storage_bucket.inner_loop_artifacts_bucket.url
}

output "tests_bucket_url" {
  value = google_storage_bucket.inner_loop_tests_bucket.url
}

output "apt_repo_name" {
  value = google_artifact_registry_repository.inner_loop_apt_repo.name
}

output "pip_repo_name" {
  value = google_artifact_registry_repository.inner_loop_pip_repo.name
}

output "result" {
  value = "finished"
}
