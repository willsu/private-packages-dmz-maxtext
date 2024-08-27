#!/bin/bash
set -x

# Currently meant to be run with the gcloud project configured to the outer loop,
# i.e. gcloud config set project $OUTER_LOOP_PROJECT

# Generate random string compatible with storage buckets names
RAND=$(cat /dev/random | head -c4 | base64 | sed 's/[/=]//g' | tr '[:upper:]' '[:lower:]')

# NOTE: The only required arguments are $1 (OUTER_PROJECT_ID) and $2 (INNER_PROJECT_ID)

# Project ID of outer loop
OUTER_PROJECT_ID=$1
OUTER_PROJECT_NUMBER=$(gcloud projects describe $OUTER_PROJECT_ID --format="value(projectNumber)")
# Project ID of inner loop
INNER_PROJECT_ID=$2
INNER_PROJECT_NUMBER=$(gcloud projects describe $INNER_PROJECT_ID --format="value(projectNumber)")
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
#TPU_ACCELERATOR_TYPE=${12:-v4-8}
TPU_RUNTIME_VERSION=${13:-tpu-ubuntu2204-base}

gcloud services enable \
  artifactregistry.googleapis.com \
  tpu.googleapis.com \
  cloudbuild.googleapis.com \
  servicenetworking.googleapis.com

gcloud services enable --project $INNER_PROJECT_ID \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  tpu.googleapis.com

gcloud iam service-accounts create cloud-build-agent-outer-loop \
  --description="Cloud Build Agent Service Account for the Outer DevOps Loop" \
  --display-name="Cloud Build Agent Outer Loop"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-outer-loop@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-outer-loop@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-outer-loop@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/tpu.admin"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-outer-loop@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-outer-loop@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

# Grant access to Artifact Registry for the default compute service account used for the TPU VM
gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:$OUTER_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:$OUTER_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/storage.objectUser"

# Create service account for the DMZ
gcloud iam service-accounts create cloud-build-agent-dmz \
  --description="Cloud Build Agent Service Account for the DMZ" \
  --display-name="Cloud Build Agent DMZ"

# Grant the DMZ service account to access Artifact Registry in the Outer Project
gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectUser"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $OUTER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

# Grant the DMZ service account to access Artifact Registry in the Inner Project
gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

# Grant the DMZ service account access to submit a built from the the Inner Project
gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"

# Grant the DMZ service account access to write the source repo to Cloud Storage on the Inner Project
gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create the Inner Loop Cloud Build Service Account
gcloud iam service-accounts create cloud-build-agent-inner-loop \
  --description="Cloud Build Agent Service Account for the Inner DevOps Loop" \
  --display-name="Cloud Build Agent Inner Loop" \
  --project=$INNER_PROJECT_ID

# Grant the DMZ service account access to use the inner project loop's Cloud Build Service Account
gcloud iam service-accounts add-iam-policy-binding cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com \
  --member="serviceAccount:cloud-build-agent-dmz@$OUTER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor" \
  --project=$INNER_PROJECT_ID

# Inner Loop SA needs access to the maxtext-artifacts bucket
# and storage buckets list permission to run maxtext tests
# TODO: replace with fine-grained permissions
gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# TPU Admin permissions for the inner project compute service account to create the TPU VM
gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/tpu.admin"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:cloud-build-agent-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

# Create the Inner Loop TPU Service Account
gcloud iam service-accounts create tpu-service-account-inner-loop \
  --description="TPU Service Account for the Inner DevOps Loop" \
  --display-name="TPU Service Account Inner Loop" \
  --project=$INNER_PROJECT_ID

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/tpu.viewer"

gcloud projects add-iam-policy-binding $INNER_PROJECT_ID \
  --member="serviceAccount:tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

# Outer Loop repos
gcloud artifacts repositories create $APT_OUTER_REPO \
  --repository-format=apt \
  --location=$REGION \
  --description="Apt Package for Outer Loop"

gcloud artifacts repositories create $PIP_OUTER_REPO \
  --repository-format=python \
  --location=$REGION \
  --description="Python Package for Outer Loop"

# Inner Loop repos
gcloud artifacts repositories create $APT_INNER_LOOP \
  --repository-format=apt \
  --location=$REGION \
  --description="Apt Package for Inner Loop" \
  --project=$INNER_PROJECT_ID

gcloud artifacts repositories create $PIP_INNER_LOOP \
  --repository-format=python \
  --location=$REGION \
  --description="Python Package for Inner Loop" \
  --project=$INNER_PROJECT_ID

# Create a storage bucket in the outer loop for package results
gsutil mb -l $REGION gs://$MAXTEXT_ARTIFACTS_BUCKET_OUTER

# Create a storage bucket in the inner loop for package results
gsutil mb -p ${INNER_PROJECT_ID} -l $REGION gs://$MAXTEXT_ARTIFACTS_BUCKET_INNER

# Create a storage bucket in the inner loop for maxtext test results
gsutil mb -p ${INNER_PROJECT_ID} -l $REGION gs://$MAXTEXT_TEST_BUCKET

# Outer Loop network components
gcloud compute networks create vpc-outer-loop \
  --subnet-mode=custom

gcloud compute networks subnets create subnet-outer-loop \
    --network=vpc-outer-loop \
    --region=$REGION \
    --range=10.0.0.0/24 \
    --enable-private-ip-google-access

gcloud compute routers create router-outer-loop \
    --network=vpc-outer-loop \
    --region=$REGION

gcloud compute routers nats create nat-outer-loop \
    --router=router-outer-loop \
    --region=$REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips

gcloud compute firewall-rules create outer-loop-allow-inbound-from-gcp \
  --network=vpc-outer-loop \
  --allow=tcp:22,icmp

# Inner Loop network components
gcloud compute networks create vpc-inner-loop \
  --subnet-mode=custom \
  --project $INNER_PROJECT_ID

gcloud compute networks subnets create subnet-inner-loop \
    --network=vpc-inner-loop \
    --region=$REGION \
    --range=10.0.1.0/24 \
    --enable-private-ip-google-access \
    --project $INNER_PROJECT_ID

gcloud compute firewall-rules create inner-loop-allow-inbound-from-gcp \
  --network=vpc-inner-loop \
  --allow=tcp:22,icmp \
  --project $INNER_PROJECT_ID

gcloud dns managed-zones create googleapis-com \
  --description="Google APIs" \
  --dns-name="googleapis.com." \
  --visibility="private" \
  --networks="vpc-inner-loop" \
  --project $INNER_PROJECT_ID

gcloud dns record-sets create "*.googleapis.com." \
  --rrdatas="googleapis.com." \
  --type=CNAME \
  --ttl=300 \
  --zone=googleapis-com \
  --project $INNER_PROJECT_ID

gcloud dns record-sets create "googleapis.com." \
  --rrdatas="199.36.153.8,199.36.153.9,199.36.153.10,199.36.153.11" \
  --type=A \
  --ttl=300 \
  --zone=googleapis-com \
  --project $INNER_PROJECT_ID

echo "Project Setup Complete"

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
  _MAXTEXT_BUCKET_URL: "gs://${MAXTEXT_ARTIFACTS_BUCKET_OUTER}"
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
  _MAXTEXT_BUCKET_INNER_URL: "gs://$MAXTEXT_ARTIFACTS_BUCKET_INNER"
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
  _MAXTEXT_TEST_BUCKET: "gs://${MAXTEXT_TEST_BUCKET}"
  _MAXTEXT_TEST_JOB_NAME: "test-job"
  _MAXTEXT_ARTIFACTS_BUCKET_INNER: "gs://$MAXTEXT_ARTIFACTS_BUCKET_INNER"
  _TPU_ACCELERATOR_TYPE: "${TPU_ACCELERATOR_TYPE}"
  _TPU_RUNTIME_VERSION: "${TPU_RUNTIME_VERSION}"
  _TPU_SERVICE_ACCOUNT: "tpu-service-account-inner-loop@$INNER_PROJECT_ID.iam.gserviceaccount.com"
  _WORKER_SERVICE_ACCOUNT: "cloud-build-agent-inner-loop@\${PROJECT_ID}.iam.gserviceaccount.com"
EOF
