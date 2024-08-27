#!/bin/bash
set -exo pipefail

# fully qualified URL of APT repo, e.g: https://us-central1-apt.pkg.dev/projects/my-project
APT_REPO_BASE_URL=$1
# name of apt repo, e.g: apt-outer-loop
APT_REPO=$2
# fully qualified URL of PIP repo, e.g: https://us-central1-python.pkg.dev/my-project
PIP_REPO_BASE_URL=$3
# name of pip repo, e.g: python-outer-loop
PIP_REPO=$4
# Artifact Registry region
REGION=$5

gcloud artifacts files list \
  --repository=${APT_REPO} \
  --location=${REGION} \
  | tail -n +2 \
  | awk '{print $1}' \
  > apt-already-stored-in-ar.out

mkdir -p apt-dist && cd apt-dist

# Copy every newly installed .deb package from the apt archives to the apt-dist directory for upload.
touch ../apt-new-packages.out
while IFS="" read -r APT_PKG || [ -n "$APT_PKG" ]
do
  SHORT_APT_PKG=$(basename $APT_PKG .deb)
  if ! grep -q $SHORT_APT_PKG ../apt-already-stored-in-ar.out; then
    echo $APT_PKG >> ../apt-new-packages.out
    ENCODED_APT_PKG=$(echo $APT_PKG | sed 's/:/%3a/g')
    cp /var/cache/apt/archives/$ENCODED_APT_PKG .
  fi
done < ../apt-new-package-candidates.out

cd ..

# Organize PIP distribution files (.whl)
gcloud artifacts files list \
  --repository=${PIP_REPO} \
  --location=${REGION} \
  | tail -n +2 \
  | awk '{print $1}' \
  > pip-already-stored-in-ar.out

mkdir -p pip-dist && cd pip-dist

# Install keyring libraries so that pip can properly authenticate with Artifact Registry
pip install keyring
pip install keyrings.google-artifactregistry-auth

set +e
read -r -d '' PYPIRC <<EOF
[distutils]
index-servers =     
    ${PIP_REPO}

[${PIP_REPO}]
repository: ${PIP_REPO_BASE_URL}/${PIP_REPO}/
EOF
set -e

echo "$PYPIRC" > ~/.pypirc

set +e
read -r -d '' PYCONF <<EOF
[global]
extra-index-url = ${PIP_REPO_BASE_URL}/${PIP_REPO}/simple/
EOF
set -e

mkdir -p ~/.pip
echo "$PYCONF" > ~/.pip/pip.conf

# Use "pip download" to download (or move from cache) all new pip packages.
# Most of the packages will be downloaded by pip as .whl files, except some special cases.
# Ignore packages with no version (git repos).
# Ignore libtpu-nightly package. 
# Note: Ignored cases will be handled explictly below.
grep "=" ../pip-new-packages-partial.out \
| grep -v "libtpu-nightly" \
| xargs -P 48 -I {} pip download {}

# Build special case .whl files for:
# 1) packages of .tar.gz format (2 total)
find . -name "*.tar.gz" \
| while read -r TAR_PKG ; do
    tar -xzf $TAR_PKG
    PKG_DIR=$(echo $TAR_PKG | sed 's/\.tar\.gz//g')
    cd $PKG_DIR
    python setup.py bdist_wheel
    cp dist/*.whl ..
    cd ..
  done

# 2) packages from Git repos (identified by no version listed in pip freeze output)
grep -v "=" ../pip-new-packages-partial.out \
| while read -r PKG ; do
    PKG_DIR="$(echo $PKG | sed "s/-/_/g")"
    DIST_DIR="$(ls -d $HOME/.local/lib/python3.10/site-packages/$PKG_DIR* \
                | grep dist-info \
                | head)"

    REPO_URL=$(sed -n 's/.*"url": "\([^"]*\)".*/\1/p' $DIST_DIR/direct_url.json)
    COMMIT_ID=$(sed -n 's/.*"commit_id": "\([^"]*\)".*/\1/p' $DIST_DIR/direct_url.json)
    # Clone the repository    
    git clone "$REPO_URL"
    cd "$(basename "$REPO_URL" .git)"
    git checkout "$COMMIT_ID"

    # Build the .whl file
    python setup.py bdist_wheel
    cp dist/*.whl ..
    cd ..
  done

# 3) There are currently problems with libtpu-nightly that require a workaround
# https://github.com/google/jax/issues/22793
LIBTPU_NIGHTLY=$(grep "libtpu-nightly" ../pip-new-packages-partial.out)
pip download ${LIBTPU_NIGHTLY} -f https://storage.googleapis.com/jax-releases/libtpu_releases.html

# Ensure that the only remaining .whl files do not already exist in Artifact Registry
# Generate the 'pip-new-package.out' file and include all new packages.
touch ../pip-new-packages.out
find . -maxdepth 1 -name "*.whl" \
| while IFS="" read -r PIP_WHL
  do
    # removes the leading "./" from the find output
    SHORT_PIP_WHL=$(echo $PIP_WHL | sed "s/.\///g")
    if ! grep -q $SHORT_PIP_WHL ../pip-already-stored-in-ar.out; then
      PIP_PKG=$(echo $PIP_WHL | sed -E "s/^.\/([^-]*)-([^-]*).*-.*/\1==\2/g")
      echo $PIP_PKG >> ../pip-new-packages.out
    else
      # Remove the .whl file if the package already exists in Artifact Registry
      # This will ensure that we don't encounter 400 series errors when the .whl files are uploaded.
      rm $PIP_WHL
    fi
  done

# Sort pip-new-packages.out to match format of 'pip freeze' output
sort -o ../pip-new-packages.out ../pip-new-packages.out
