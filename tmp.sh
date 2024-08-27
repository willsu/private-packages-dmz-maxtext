gcloud artifacts packages list \
  --repository=pip-outer-loop \
  --project=maxtext-qa-outer-8 \
  --location=us-central1
gcloud artifacts versions list --package=projects/maxtext-qa-outer-8/locations/us-central1/repositories/pip-outer-loop/packages/zipp --location us-central1 --repository pip-outer-loop/ --format "value(name)"
