#!/bin/bash
set -exo pipefail

# fully qualified URL of APT repo, e.g: https://us-central1-apt.pkg.dev/projects/your-project
APT_REPO_BASE_URL=$1
# name of apt repo, e.g: apt-outer-loop
APT_REPO=$2

# fully qualified URL of PIP repo, e.g: https://us-central1-python.pkg.dev/your-project
PIP_REPO_BASE_URL=$3
# name of pip repo, e.g: ${PIP_REPO}
PIP_REPO=$4

# Cloud Storage URL of maxtext codebase, e.g: gs://maxtext-artifacts/maxtext-latest.zip
MAXTEXT_SRC_URL=$5

# Artifact Registry repo region
REGION=$6

# Ensure we don't get interactive prompts when we run apt update commands
sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf

# Stop unattended-upgrades to avoid contention for apt install/upgrade commands
sudo systemctl stop unattended-upgrades

# Move the default auto-upgrades config out of the apt.conf dir to block subsequent auto-upgrades
sudo mv /etc/apt/apt.conf.d/20auto-upgrades ./20auto-upgrades.bak

mkdir -p "${HOME}/apt_dist" && cd "${HOME}/apt_dist"

# Download the APT Artifact Registry package from Artifact Registry
APT_AR_TRANSPORT_PKG="$(
  gcloud artifacts files list \
    --repository=${APT_REPO} \
    --location=${REGION} \
    --package=apt-transport-artifact-registry | tail -n1 | awk '{print $1}'
)"

gcloud artifacts files download \
  --location=${REGION} \
  --repository=${APT_REPO} \
  --destination=. \
  $APT_AR_TRANSPORT_PKG

# The actual file will be downloaded with an encoded "/" as "%2F"
APT_AR_FILE_NAME="$(echo $APT_AR_TRANSPORT_PKG | sed 's/\//%2F/g' | sed 's/\:/%3A/g')"
# Truncate everything up to the encoded "/" ("%2F") for ease of package installation
APT_AR_SHORT_NAME="$(echo $APT_AR_FILE_NAME | sed 's/.*%2F//g')"
# Rename the file to the truncated version
mv $APT_AR_FILE_NAME $APT_AR_SHORT_NAME

# Install the APT Artifact Registry package
sudo dpkg -i $APT_AR_SHORT_NAME

cd $HOME

# Disable all current apt sources. These will be unreachable through the network and cause timeouts and other problems.
mkdir -p "${HOME}/apt_sources_bak"
sudo mv /etc/apt/sources.list.d/* "${HOME}/apt_sources_bak" || true
sudo mv /etc/apt/sources.list "${HOME}/apt_sources_bak" || true

# Configure APT to use the Artifact Registry repository
echo "deb ar+${APT_REPO_BASE_URL} ${APT_REPO} main" \
| sudo tee -a /etc/apt/sources.list.d/artifact-registry.list

# Add Artifact Registry package signing key
curl https://${REGION}-apt.pkg.dev/doc/repo-signing-key.gpg \
| sudo apt-key add - && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
| sudo apt-key add -

# Allow apt to update gcsfuse libary since the origin and label may have changed from the stock installation.
sudo apt update --allow-releaseinfo-change

# We are required to explictly install the keyring dependencies since we
# have no access to our Artifact Registry Pip index at this point in the setup.
KEYRING_PKGS=(
  "importlib-metadata"
  "backports.tarfile"
  "jaraco.classes"
  "jaraco.context"
  "jaraco.functools"
  "keyring"
  "pluggy"
  "rsa"
  "cachetools"
  "google-auth"
  "pyasn1-modules"
  "keyrings.google-artifactregistry-auth"
)

mkdir -p "${HOME}/pip_dist" && cd "${HOME}/pip_dist"

for KEYRING_PKG in ${KEYRING_PKGS[@]}; do
  PKG_FULL_NAME="$(
    gcloud artifacts files list \
      --repository=${PIP_REPO} \
      --location=${REGION} \
      --package=${KEYRING_PKG} | tail -n1 | awk '{print $1}'
  )"

  if [ ! -z ${PKG_FULL_NAME} ]; then
    gcloud artifacts files download \
      --location=${REGION} \
      --repository=${PIP_REPO} \
      --destination=. \
      $PKG_FULL_NAME
  else
    echo "The PIP package: ${KEYRING_PKG} could not be found. Please verify that it exists in the repository"
    exit 1
  fi

  # The actual file will be downloaded with an encoded "/" as "%2F"
  PKG_FILE_NAME="$(echo $PKG_FULL_NAME | sed 's/\//%2F/g')"
  # Truncate everything up to the encoded "/" ("%2F") for ease of package installation
  PKG_SHORT_NAME="$(echo $PKG_FILE_NAME | sed 's/.*%2F//g')"
  # Rename the file to the truncated version
  mv $PKG_FILE_NAME $PKG_SHORT_NAME

  # Install the Artifact Registry keyring and dependent packages
  pip install --no-index $PKG_SHORT_NAME
done

cd $HOME

# Configure Pip to use Artifact Registry

# TODO: why are these 'read' commands returning non-0?
set +e
read -r -d '' PYPIRC <<EOF
[distutils]
index-servers =     
    ${PIP_REPO}

[${PIP_REPO}]
repository: ${PIP_REPO_BASE_URL}/${PIP_REPO}/
EOF
set -e

echo "$PYPIRC" > $HOME/.pypirc

# TODO: why are these 'read' commands returning non-0?
set +e
read -r -d '' PYCONF <<EOF
[global]
index-url = ${PIP_REPO_BASE_URL}/${PIP_REPO}/simple/
EOF
set -e

mkdir -p ~/.pip
echo "$PYCONF" > $HOME/.pip/pip.conf

# Add python executables to PATH
PATH="${PATH}:~/.local/bin"

# Download the Maxtext codebase
gsutil cp ${MAXTEXT_SRC_URL} .
tar -xzf $(basename "$MAXTEXT_SRC_URL")

# Install Maxtext LLM
cd maxtext
bash -ex setup.sh
pre-commit install

# Start unattended-upgrades now that we're finished using Apt 
sudo systemctl start unattended-upgrades
