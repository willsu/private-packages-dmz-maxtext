variable "outer_project_id" {
  type = string
  description = "Project ID of the outer loop"
}

variable "outer_project_number" {
  type = string
  description = "Project ID of the outer loop"
}

variable "inner_project_id" {
  type = string
  description = "Project ID of the inner loop"
}

variable "region" {
  type = string
  default = "us-central1"
  description = "Region for all cloud services"
}

variable "zone" {
  type = string
  default = "us-central1-a"
  description = "Zone for TPU VM"
}

variable "apt_outer_repo" {
  type = string
  default = "apt-outer-loop"
  description = "Artifact Registry repository name for APT packages in the outer loop"
}

variable "pip_outer_repo" {
  type = string
  default = "pip-outer-loop"
  description = "Artifact Registry repository name for PIP packages in the outer loop"
}

variable "apt_inner_repo" {
  type = string
  default = "apt-inner-loop"
  description = "Artifact Registry repository name for APT packages in the inner loop"
}

variable "pip_inner_repo" {
  type = string
  default = "pip-inner-loop"
  description = "Artifact Registry repository name for PIP packages in the inner loop"
}

variable "tpu_accelerator_type" {
  type = string
  default = "v3-8"
  description = "TPU Accelerator Type"
}

variable "tpu_runtime_version" {
  type = string
  default = "tpu-ubuntu2204-base"
  description = "TPU Runtime Version"
}
