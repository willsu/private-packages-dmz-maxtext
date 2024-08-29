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

resource "null_resource" "cloud_build_template_output" {
  provisioner "local-exec" {
    command     = <<-EOF
    ${path.cwd}/cloud-build-template-values.sh \
      ${var.outer_project_id} \
      ${var.inner_project_id} \
      ${var.region} \
      ${var.zone} \
      ${module.outer_loop.artifacts_bucket_url} \
      ${module.inner_loop.artifacts_bucket_url} \
      ${module.inner_loop.tests_bucket_url} \
      ${module.outer_loop.apt_repo_name} \
      ${module.outer_loop.pip_repo_name} \
      ${module.inner_loop.apt_repo_name} \
      ${module.inner_loop.pip_repo_name} \
      ${var.tpu_accelerator_type} \
      ${var.tpu_runtime_version}
    EOF

    interpreter = ["bash", "-c"]
  }
  depends_on = [module.outer_loop.result, module.inner_loop.result, module.dmz.result]
  triggers = {
    always_run = "${timestamp()}"
  }
}
