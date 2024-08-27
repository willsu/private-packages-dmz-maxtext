#!/bin/bash
set -exo pipefail

# temporarily disable tests until TPU V4-V5 becomes available
exit 0

MAXTEXT_TEST_JOB_NAME=$1
MAXTEXT_TEST_BUCKET=$2

cd maxtext

python3 MaxText/train.py MaxText/configs/base.yml \
  run_name=$1 \
  base_output_directory=$2 \
  dataset_type=synthetic \
  steps=10
