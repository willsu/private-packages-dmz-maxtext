variable outer_project_id {}
variable outer_project_number {}
variable apt_outer_repo {}
variable region {}
variable pip_outer_repo {}
variable bucket_suffix {}
variable api_enablement_result {}

resource "google_service_account" "outer_loop_cloud_build_agent" {
  account_id   = "cloud-build-agent-outer-loop"
  display_name = "Cloud Build Agent Outer Loop"
  project      = var.outer_project_id
  disabled     = false
}

# Grant IAM Permissions for Outer Loop Service Accounts
resource "google_project_iam_member" "outer_loop_cloud_build_agent_roles" {
  project = var.outer_project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.outer_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "outer_loop_cloud_build_agent_iap" {
  project = var.outer_project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.outer_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "outer_loop_cloud_build_agent_tpu_admin" {
  project = var.outer_project_id
  role    = "roles/tpu.admin"
  member  = "serviceAccount:${google_service_account.outer_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "outer_loop_cloud_build_agent_service_account_user" {
  project = var.outer_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.outer_loop_cloud_build_agent.email}"
}

resource "google_project_iam_member" "outer_loop_cloud_build_agent_compute_admin" {
  project = var.outer_project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.outer_loop_cloud_build_agent.email}"
}

# Grant IAM Permissions for the Default Compute Service Account
resource "google_project_iam_member" "outer_loop_compute_service_account_artifact_registry_admin" {
  project = var.outer_project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${var.outer_project_number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "outer_loop_compute_service_account_storage_object_user" {
  project = var.outer_project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${var.outer_project_number}-compute@developer.gserviceaccount.com"
}


# Outer Loop Artifact Registry Repositories
resource "google_artifact_registry_repository" "outer_loop_apt_repo" {
  format = "apt"
  location = var.region
  repository_id = var.apt_outer_repo
  project = var.outer_project_id
  description = "Apt Package for Outer Loop"
}

resource "google_artifact_registry_repository" "outer_loop_pip_repo" {
  format = "python"
  location = var.region
  repository_id = var.pip_outer_repo
  project = var.outer_project_id
  description = "Python Package for Outer Loop"
}

# Outer Loop Storage Buckets
resource "google_storage_bucket" "outer_loop_artifacts_bucket" {
  name     = "maxtext-artifacts-outer-${var.bucket_suffix}"
  location = var.region
  force_destroy = true
  project     = var.outer_project_id
  uniform_bucket_level_access = true
}

# Outer Loop Network Components
resource "google_compute_network" "outer_loop_network" {
  name     = "vpc-outer-loop"
  auto_create_subnetworks = false
  project = var.outer_project_id
  routing_mode = "REGIONAL"
}

resource "google_compute_subnetwork" "outer_loop_subnet" {
  name      = "subnet-outer-loop"
  ip_cidr_range = "10.0.0.0/24"
  project  = var.outer_project_id
  region   = var.region
  network  = google_compute_network.outer_loop_network.self_link
  private_ip_google_access = true
}

resource "google_compute_router" "outer_loop_router" {
  name     = "router-outer-loop"
  project = var.outer_project_id
  region   = var.region
  network  = google_compute_network.outer_loop_network.self_link
}

resource "google_compute_router_nat" "outer_loop_nat" {
  name = "nat-outer-loop"
  project     = var.outer_project_id
  region     = var.region
  router     = google_compute_router.outer_loop_router.name
  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "outer_loop_allow_inbound_from_gcp" {
  name     = "outer-loop-allow-inbound-from-gcp"
  project  = var.outer_project_id
  network  = google_compute_network.outer_loop_network.self_link
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