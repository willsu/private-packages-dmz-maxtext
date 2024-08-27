#!/bin/bash
set -exo pipefail

# inner project id
INNER_PROJECT_ID=$1
# outer project id
OUTER_PROJECT_ID=$2
# name of apt repo, e.g: apt-outer-loop
OUTER_APT_REPO_NAME=$3
# name of apt repo, e.g: apt-inner-loop
INNER_APT_REPO_NAME=$4
# fully qualified URL of PIP repo, e.g: https://us-central1-python.pkg.dev/your-inner-project
INNER_PIP_REPO_BASE_URL=$5
# name of pip repo, e.g: pip-inner-loop
INNER_PIP_REPO=$6
# fully qualified URL of PIP repo, e.g: https://us-central1-python.pkg.dev/your-outer-project
OUTER_PIP_REPO_BASE_URL=$7
# name of pip repo, e.g: pip-outer-loop
OUTER_PIP_REPO=$8
# Cloud Storage URL of package list artifacts
BUILD_ARTIFACTS_URL=$9
# Fail if vulnerable package upload is detected
FAIL_ON_VULN=${10}
# Region for outer and inner loop package repos
REGION=${11}
# Maxtext Inner Loop Bucket
MAXTEXT_BUCKET_INNER_URL=${12}

# Defaults to "0", meaning that no vulnerable packages were attempted to be uploaded.
# This var will be set to "1" if any vulnerabilities are found in apt or pip.
VULN_FOUND="0"

# Download artifact list from latest outer loop run
gsutil cp $BUILD_ARTIFACTS_URL .
# Install jq
apt-get install -y jq

# Download the associated artifacts
ARTIFACTS_FILE=$(basename $BUILD_ARTIFACTS_URL)
jq -r .location $ARTIFACTS_FILE \
| xargs -I {} gsutil cp {} .

# Copy the Maxtext src repo to the inner loop cloud storage bucket
MAXTEXT_SRC_URL=$(<maxtext-src-url.out)
MAXTEXT_SRC_INNER_URL="${MAXTEXT_BUCKET_INNER_URL}/$(basename $MAXTEXT_SRC_URL)"
gsutil cp $MAXTEXT_SRC_URL $MAXTEXT_SRC_INNER_URL
echo "$MAXTEXT_SRC_INNER_URL" > maxtext-src-inner-url.out

# Copy all required APT packages from outer to inner loop
mkdir -p apt-dist && cd apt-dist

while IFS="" read -r APT_PKG || [ -n "$APT_PKG" ]
do
  # Protect against a empty lines
  if [ "$APT_PKG" = "" ]; then continue; fi

  # Canonicalize package name version for lookup
  PKG_SHORT_NAME=$(echo $APT_PKG | sed "s/_.*//g")
  PKG_VERSION=$(echo $APT_PKG | sed -r "s/.*_(.*)_.*/\1/g")

  # Download the APT Artifact Registry package from Artifact Registry
  APT_AR_PKG="$(
    gcloud artifacts files list \
      --repository=${OUTER_APT_REPO_NAME} \
      --project=${OUTER_PROJECT_ID} \
      --location=${REGION} \
      --package=${PKG_SHORT_NAME} \
      --version=${PKG_VERSION} \
      --format="value(name)"
  )"

  # Download the .deb file 
  gcloud artifacts files download \
    --project=${OUTER_PROJECT_ID} \
    --location=${REGION} \
    --repository=${OUTER_APT_REPO_NAME} \
    --destination=. \
  $APT_AR_PKG
done < ../apt-new-packages.out

# Upload all .deb files
ARCH=$(dpkg --print-architecture)

# Note: Process substitution is used for this while loop to ensure
# that any changes to VULN_FOUND will be reflected in the current process.
while read -r APT_PKG ; do
  # Generate the deb cache compatible name that is used for lookup in the vulnerability file
  # e.g. ./pool%2Fnet-tools_1.60%2Bgit20181103.0eebece-1ubuntu5_amd64_4def95f207c168728f36d3ada2f8d32f.deb ->
  # net-tools_1.60+git20181103.0eebece-1ubuntu5_amd64.deb
  APT_PKG_SHORT=$(echo $APT_PKG | sed 's/%2B/+/g' | sed -E "s/.*%2F(.*_${ARCH}).*/\1.deb/g")
  if grep -q ${APT_PKG_SHORT} ../apt-new-vuln-results.out; then
    APT_FULL_SCAN_RESULTS=$(grep "apt-scan-full-results.json" "../${ARTIFACTS_FILE}" | jq -r .location)
    echo "Skipping upload of vulnerable apt package: '${APT_PKG_SHORT}'. \
        Please see full vulnerability list for more details at: ${APT_FULL_SCAN_RESULTS}"
    VULN_FOUND="1" && continue
  fi
  gcloud artifacts apt upload ${INNER_APT_REPO_NAME} \
    --project=${INNER_PROJECT_ID} \
    --location=${REGION} \
    --source=${APT_PKG}
done < <(find . -name "*.deb")

cd ..

# Copy all required PIP packages from outer to inner loop
mkdir -p pip-dist && cd pip-dist

# Download all PIP images from the list.
while IFS="" read -r PIP_PKG || [ -n "$PIP_PKG" ]
do
  # Canonicalize package name version for lookup
  PKG_SHORT_NAME=$(echo $PIP_PKG | sed "s/==.*//g" | sed "s/_/-/g")
  # TODO: make the sed expression smarter and remove the grep
  # The line items without "==" do not have a version, so we want to ensure that PKG_VERSION is blank
  # so that the gcloud commands below work as expected.
  PKG_VERSION=$(echo $PIP_PKG | { grep "==" || true; } | sed -r "s/.*==(.*)/\1/g")

  # Download the APT Artifact Registry package from Artifact Registry
  # Note: If the package cannot be found, attempt to look it up by it's capitalized name.
  # This fixed package sync-ing for Pygments, Werkzeug, and Jinja2.
  # TODO: Find a more deterministic way to look up the package name by it's correctly capitalized name.
  PIP_AR_PKG="$(
    gcloud artifacts files list \
      --repository=${OUTER_PIP_REPO} \
      --project=${OUTER_PROJECT_ID} \
      --location=${REGION} \
      --package=${PKG_SHORT_NAME} \
      --version=${PKG_VERSION} \
      --format="value(name)"
  )" &&
  [ ! -z $PIP_AR_PKG ] || \
  PIP_AR_PKG="$(
    gcloud artifacts files list \
      --repository=${OUTER_PIP_REPO} \
      --project=${OUTER_PROJECT_ID} \
      --location=${REGION} \
      --package=${PKG_SHORT_NAME^} \
      --version=${PKG_VERSION} \
      --format="value(name)"
  )" &&
  # Download the .whl file 
  gcloud artifacts files download \
    --project=${OUTER_PROJECT_ID} \
    --location=${REGION} \
    --repository=${OUTER_PIP_REPO} \
    --destination=. \
  $PIP_AR_PKG &
  while [ $(jobs -l | wc -l) -ge 48 ]
  do
    sleep .1
  done
done < ../pip-new-packages.out
# ensure that all jobs have finished
wait

# Install twine and the keyring libraries from the PyPi index
# before replacing index with the Artifact Registry repo url
pip install twine
pip install keyring
pip install keyrings.google-artifactregistry-auth

# Configure PIP for Artifact Registry authentication.
set +e
read -r -d '' PYPIRC <<EOF
[distutils]
index-servers =     
    ${INNER_PIP_REPO}

[${INNER_PIP_REPO}]
repository: ${INNER_PIP_REPO_BASE_URL}/${INNER_PIP_REPO}/
EOF
set -e

echo "$PYPIRC" > $HOME/.pypirc

# TODO: why are these 'read' commands returning non-0?
set +e
read -r -d '' PYCONF <<EOF
[global]
index-url = ${INNER_PIP_REPO_BASE_URL}/${INNER_PIP_REPO}/simple/
EOF
set -e

mkdir -p ~/.pip
echo "$PYCONF" > $HOME/.pip/pip.conf

# Note: Process substitution is used for this while loop to ensure
# that any changes to VULN_FOUND will be reflected in the current process.
while read -r PIP_WHL ; do
  # Protect against an empty lines
  if [ "$PIP_WHL" = "" ]; then continue; fi
  # avoid double namespacing issue by truncating the first noun in the path
  # e.g. if we upload "importlib-metadata%2Fimportlib_metadata-8.0.0-py3-none-any.whl",
  # we'll result in a pip package file importlib-metadata/importlib-metadata/importlib_metadata-8.0.0-py3-none-any.whl in
  # Artifact Registry and will cause problems in the inner-loop
  SHORT_PIP_WHL_NAME=$(echo $PIP_WHL | sed 's/.*%2F//g')
  mv $PIP_WHL $SHORT_PIP_WHL_NAME

  # Transform short pip whl file name to pip package name to match vulnerability list
  # E.g tensorboard-2.17.1-py3-none-any.whl -> tensorboard==2.17.1
  PIP_PKG=$(echo $SHORT_PIP_WHL_NAME | sed -E "s/^([^-]*)-([^-]*).*-.*/\1==\2/g")
  if grep -q ${PIP_PKG} ../pip-new-vuln-results.out; then
    # Do not upload if the package is in the vulnerability list
    PIP_FULL_SCAN_RESULTS=$(grep "pip-scan-full-results.json" "../${ARTIFACTS_FILE}" | jq -r .location)
    echo "Skipping upload of vulnerable pip package: '${PIP_PKG}' in whl file: '${SHORT_PIP_WHL_NAME}'. \
        Please see full vulnerability list for more details at: ${PIP_FULL_SCAN_RESULTS}"
    VULN_FOUND="1" && continue
  fi

  python3 -m twine upload \
    --skip-existing \
    --repository-url "$INNER_PIP_REPO_BASE_URL/$INNER_PIP_REPO/" $SHORT_PIP_WHL_NAME
done < <(find . -name "*.whl")

cd ..

if [ $VULN_FOUND = "1" ] && [ $FAIL_ON_VULN = "1" ]; then
  echo "Vulnerabiliities were detected on apt or pip packages, and their upload was skipped.
        Please search the build logs for 'skipping' for more information on the specfic packages
        with vulnerabilities. To allow this builds to pass, regardless of whether vulnerabilites
        were found, set FAIL_ON_VULN to 0"
  exit 1
fi
