#!/bin/bash
set -exo pipefail

APT_REPO=$1
PIP_REPO_BASE_URL=$2
PIP_REPO=$3
MAXTEXT_BUCKET_URL=$4
REGION=$5

# Upload all the .deb packages to Artifact Registry
cd apt-dist
find . -maxdepth 1 -name "*.deb" \
| xargs -P 20 -I {} gcloud artifacts apt upload ${APT_REPO} \
    --location=${REGION} \
    --source={}
cd ..

# Upload all packages
pip install twine
cd pip-dist
find . -maxdepth 1 -name "*.whl" \
| while read -r PIP_PKG ; do
    python3 -m twine upload \
      --skip-existing \
      --repository-url "${PIP_REPO_BASE_URL}/${PIP_REPO}/" ${PIP_PKG}
  done
cd ..

# Upload Maxtext Repo to Cloud Storage for Inner Loop
cd maxtext
GIT_SHA=$(git rev-parse --short HEAD)
cd ..

tar -czf maxtext.tar.gz maxtext
# Upload with git SHA to in object name.
MAXTEXT_SRC_URL="${MAXTEXT_BUCKET_URL}/maxtext-${GIT_SHA}.tar.gz"
gsutil cp maxtext.tar.gz $MAXTEXT_SRC_URL
echo $MAXTEXT_SRC_URL > maxtext-src-url.out
# Upload this version to maxtext-latest.tar.gz
gsutil cp maxtext.tar.gz ${MAXTEXT_BUCKET_URL}/maxtext-latest.tar.gz
