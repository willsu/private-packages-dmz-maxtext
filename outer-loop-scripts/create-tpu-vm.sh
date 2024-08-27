#!/bin/bash
set -exo pipefail

TPU_VM_NAME=$1
TPU_ACCELERATOR_TYPE=$2
TPU_RUNTIME_VERSION=$3
ZONE=$4

if [ -z "$(gcloud compute tpus tpu-vm describe ${TPU_VM_NAME} --zone=${ZONE} || \'\')" ]
then
    echo "Creating TPU tpu-vm"
    gcloud alpha compute tpus tpu-vm create ${TPU_VM_NAME} \
    --zone=${ZONE} \
    --accelerator-type=${TPU_ACCELERATOR_TYPE} \
    --version=${TPU_RUNTIME_VERSION} \
    --network=vpc-outer-loop \
    --subnetwork=subnet-outer-loop \
    --shielded-secure-boot \
    --spot \
    --internal-ips
else
    echo "TPU tpu-vm already exists"
fi
