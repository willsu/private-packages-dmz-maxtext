#!/bin/bash

if [ "$#" -ne 13 ]; then
  echo "This script requires exactly 13 arguments."
  exit 1
fi

# Project ID of outer loop
OUTER_PROJECT_ID=$1
# Project ID of inner loop
INNER_PROJECT_ID=$2
# Region for all cloud services
REGION=${3:-"us-central1"}
# Zone for TPU VM
ZONE=${4:-"us-central1-a"}
# Globally unique name of cloud storage bucket to store new package lists and other metadata in outer loop
MAXTEXT_ARTIFACTS_BUCKET_OUTER=${5:-"maxtext-artifacts-outer-${RAND}"}
# Globally unique name of cloud storage bucket to store new package lists and other metadata in inner loop
MAXTEXT_ARTIFACTS_BUCKET_INNER=${6:-"maxtext-artifacts-inner-${RAND}"}
# Globally unique name of cloud storage bucket to store maxtext runtime data in inner loop
MAXTEXT_TEST_BUCKET=${7:-"maxtext-tests-${RAND}"}
# Artifact Registry Repo Names
APT_OUTER_REPO=${8:-"apt-outer-loop"}
PIP_OUTER_REPO=${9:-"pip-outer-loop"}
APT_INNER_LOOP=${10:-"apt-inner-loop"}
PIP_INNER_LOOP=${11:-"pip-inner-loop"}

# TPU Type and Runtime
TPU_ACCELERATOR_TYPE=${12:-v3-8}
TPU_RUNTIME_VERSION=${13:-tpu-ubuntu2204-base}

cat << EOF
Replace the following subsitution values in the outer-loop-scripts/cloud.yaml file (near the top):
Note: The output will include unevaluated vars such as \${PROJECT_ID}. These vars will be evaluated by Cloud Build.
  _REGION: "$REGION"
  _ZONE: "$ZONE"
  _APT_REPO_BASE_URL: "https://${REGION}-apt.pkg.dev/projects/\${PROJECT_ID}"
  _APT_REPO_NAME: "$APT_OUTER_REPO"
  _PIP_REPO_BASE_URL: "https://${REGION}-python.pkg.dev/\${PROJECT_ID}"
  _PIP_REPO_NAME: "$PIP_OUTER_REPO"
  _TPU_VM_NAME: "tpu-outer-loop-ci"
  _MAXTEXT_GIT_URL: "https://github.com/google/maxtext.git"
  _MAXTEXT_BUCKET_URL: "${MAXTEXT_ARTIFACTS_BUCKET_OUTER}"
  _TPU_ACCELERATOR_TYPE: "${TPU_ACCELERATOR_TYPE}"
  _TPU_RUNTIME_VERSION: "${TPU_RUNTIME_VERSION}"
  _WORKER_SERVICE_ACCOUNT: "cloud-build-agent-outer-loop@\${PROJECT_ID}.iam.gserviceaccount.com"
EOF

cat << EOF
Replace the following subsitution values in the dmz-scripts/cloud.yaml file (near the top):
  _REGION: "$REGION"
  _OUTER_PROJECT_ID: "\${PROJECT_ID}"
  _OUTER_APT_REPO_NAME: "$APT_OUTER_REPO"
  _OUTER_PIP_BASE_URL: "https://\${_REGION}-apt.pkg.dev/projects/\${PROJECT_ID}"
  _OUTER_PIP_REPO_NAME: "$PIP_OUTER_REPO"
  _INNER_PROJECT_ID: "${INNER_PROJECT_ID}"
  _INNER_APT_REPO_NAME: "$APT_INNER_LOOP"
  _INNER_PIP_BASE_URL: "https://\${_REGION}-python.pkg.dev/\${_INNER_PROJECT_ID}"
  _INNER_PIP_REPO_NAME: "$PIP_INNER_LOOP"
  _MAXTEXT_BUCKET_INNER_URL: "$MAXTEXT_ARTIFACTS_BUCKET_INNER"
  _WORKER_SERVICE_ACCOUNT: "cloud-build-agent-dmz@\${_OUTER_PROJECT_ID}.iam.gserviceaccount.com"
  _FAIL_ON_VULN: "0"
  # _BUILD_ARTIFACTS_URL will be substituted dynamically when the outer-loop submits a build for the dmz.
  _BUILD_ARTIFACTS_URL: "<substituted at runtime>"
EOF

cat << EOF
Replace the following subsitution values in the inner-loop-scripts/cloud.yaml file (near the top):
  _REGION: "$REGION"
  _ZONE: "$ZONE"
  _APT_REPO_BASE_URL: "https://\${_REGION}-apt.pkg.dev/projects/\${PROJECT_ID}"
  _APT_REPO_NAME: "$APT_INNER_LOOP"
  _PIP_REPO_BASE_URL: "https://\${_REGION}-python.pkg.dev/\${PROJECT_ID}"
  _PIP_REPO_NAME: "$PIP_INNER_LOOP"
  _TPU_VM_NAME: "tpu-inner-loop-ci"
  # _MAXTEXT_SRC_URL will be substitued dynamically when the dmz submits a build for the inner loop.
  _MAXTEXT_SRC_URL: "<replaced at runtime>"
  _MAXTEXT_TEST_BUCKET: "${MAXTEXT_TEST_BUCKET}"
  _MAXTEXT_TEST_JOB_NAME: "test-job"
  _MAXTEXT_ARTIFACTS_BUCKET_INNER: "$MAXTEXT_ARTIFACTS_BUCKET_INNER"
  _TPU_ACCELERATOR_TYPE: "${TPU_ACCELERATOR_TYPE}"
  _TPU_RUNTIME_VERSION: "${TPU_RUNTIME_VERSION}"
  _TPU_SERVICE_ACCOUNT: "tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com"
  _WORKER_SERVICE_ACCOUNT: "cloud-build-agent-inner-loop@\${PROJECT_ID}.iam.gserviceaccount.com"
EOF
