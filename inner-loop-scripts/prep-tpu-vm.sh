#!/bin/bash
set -exo pipefail

TPU_VM_NAME=$1
ZONE=$2

# Proactively delete SSH keys so the service account doesn't hit the 32 key limit.
for KEY in $(gcloud compute os-login ssh-keys list | tail -n +2);
do
  gcloud compute os-login ssh-keys remove --key $KEY;
done

# Copy scripts to the TPU
gcloud alpha compute tpus tpu-vm scp \
  inner-loop-scripts/setup-inner.sh \
  inner-loop-scripts/run-maxtext-tests.sh \
  inner-loop-scripts/print-installed-packages.sh \
  ${TPU_VM_NAME}: \
  --worker=all \
  --zone=${ZONE} \
  --tunnel-through-iap

# Add the newly generated Compute Engine ssh key to improve performance
eval $(ssh-agent)
ssh-add ~/.ssh/google_compute_engine
