## Terraform Code for GCP Setup Script

# Configure the GCP Provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.18"
    }
  }
}

# Create a random string for bucket names
resource "random_string" "bucket_suffix" {
  length  = 4
  lower   = true
  numeric = false
  upper   = false
  special = false
}

module "enable_apis" {
  source = "./enable_apis"
  outer_project_id = var.outer_project_id
  inner_project_id = var.inner_project_id
}

# Call the submodules
module "outer_loop" {
  source = "./outer_loop"
  outer_project_id = var.outer_project_id
  outer_project_number = var.outer_project_number
  region = var.region
  apt_outer_repo = var.apt_outer_repo
  pip_outer_repo = var.pip_outer_repo
  bucket_suffix = random_string.bucket_suffix.result
  api_enablement_result = module.enable_apis.result
}

module "inner_loop" {
  source = "./inner_loop"
  inner_project_id = var.inner_project_id
  region = var.region
  apt_inner_repo = var.apt_inner_repo
  pip_inner_repo = var.pip_inner_repo
  bucket_suffix = random_string.bucket_suffix.result
  api_enablement_result = module.enable_apis.result
}

module "dmz" {
  source = "./dmz"
  outer_project_id = var.outer_project_id
  inner_project_id = var.inner_project_id
  inner_loop_cloud_build_agent_email = module.inner_loop.cloud_build_agent_email
  api_enablement_result = module.enable_apis.result
}
