#!/bin/bash
set -exo pipefail

TPU_VM_NAME=$1
MAXTEXT_GIT_URL=$2
ZONE=$3

# Clone the latest commit of the repo
git clone --depth 1 $MAXTEXT_GIT_URL

# Proactively delete SSH keys so the service account doesn't hit the 32 key limit.
for KEY in $(gcloud compute os-login ssh-keys list | tail -n +2);
do
  gcloud compute os-login ssh-keys remove --key $KEY;
done

# TODO: combine these scp commands. This script is running ridiculously slow
gcloud alpha compute tpus tpu-vm scp \
  outer-loop-scripts/install-max-text-on-tpu.sh \
  outer-loop-scripts/organize-package-distributions-on-tpu.sh \
  outer-loop-scripts/scan-packages-on-tpu.sh \
  outer-loop-scripts/upload-packages-on-tpu.sh \
  ${TPU_VM_NAME}: \
  --worker=all \
  --zone=${ZONE} \
  --tunnel-through-iap

gcloud alpha compute tpus tpu-vm scp \
  ./maxtext \
  ${TPU_VM_NAME}: \
  --worker=all \
  --zone=${ZONE} \
  --recurse \
  --tunnel-through-iap

# Add the newly generated Compute Engine ssh key to improve performance
eval $(ssh-agent)
ssh-add ~/.ssh/google_compute_engine
