#!/bin/bash
set -exo pipefail

INNER_PROJECT_ID=$1
REGION=$2

MAXTEXT_SRC_URL=$(<maxtext-src-inner-url.out)
gcloud builds submit \
  --project=${INNER_PROJECT_ID} \
  --async \
  --substitutions="_MAXTEXT_SRC_URL=${MAXTEXT_SRC_URL}" \
  --region ${REGION} \
  --config inner-loop-scripts/cloudbuild.yaml \
  .
