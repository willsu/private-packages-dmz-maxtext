#!/bin/bash
# Note: Didn't set the 'o pipefail' mode due to the 'diff' commands below returning non-0 exit codes
set -ex

REGION=$1

# Generate the installed APT and PIP packages before maxtext installation 
dpkg-query -W -f='${Package}_${Version}_${ARCHITECTURE}.deb\n' > apt-pre-installed.out
pip freeze > pip-pre-installed.out

# Stop unattended-upgrades to avoid contention for apt install/upgrade commands
sudo systemctl stop unattended-upgrades

# Move the default auto-upgrades config out of the apt.conf dir to block subsequent auto-upgrades
sudo mv /etc/apt/apt.conf.d/20auto-upgrades ./20auto-upgrades.bak

# Preserve .deb files in the local filesystem cache directory for ease of upload to Artifact Registry 
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' | sudo tee /etc/apt/apt.conf.d/99-keep-deb-pkgs

# Allow apt to update gcsfuse libary since the origin and label may have changed from the stock installation.
sudo apt-get update --allow-releaseinfo-change

# Pre-installation Maxtext Fix
# Fix bug in script where '$GCSFUSE_REPO' evaluates to empty due to use of 'export'
sed -i 's/\$GCSFUSE_REPO/gcsfuse-\`lsb_release -c -s\`/g' maxtext/setup.sh

# Run maxtext setup.sh script to install all the packages
cd maxtext && bash -ex setup.sh

# Post-installation Maxtext Fix
# Remove the git url from the requirements.txt list to ensure the package is fetch from Artifact Registry.
# The git URL will break package installation in the inner loop since there is no connectivity to github.
sed -i "s/@.*//g" requirements.txt

cd ..

# Install additional Artifact Registry APT and PIP authentication libraries for the inner loop.

# 1) Install the Apt Artifact Registry integration library for use in the inner loop.
curl https://${REGION}-apt.pkg.dev/doc/repo-signing-key.gpg \
| sudo apt-key add - && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
| sudo apt-key add -

echo 'deb http://packages.cloud.google.com/apt apt-transport-artifact-registry-stable main' \
| sudo tee -a /etc/apt/sources.list.d/artifact-registry.list

sudo NEEDRESTART_MODE=a apt update
sudo apt install apt-transport-artifact-registry

# 2) Install keyring .whl files and dependencies for use in the inner loop.
pip install keyring
pip install keyrings.google-artifactregistry-auth

# Generate the installed APT and PIP packages after maxtext installation 
dpkg-query -W -f='${Package}_${Version}_${ARCHITECTURE}.deb\n' > apt-post-installed.out
pip freeze > pip-post-installed.out

# Generate new packages list from the diff of pre/post install files
diff apt-pre-installed.out apt-post-installed.out \
| grep '>' \
| awk '{print $2}' > apt-new-package-candidates.out

# The "../pip-new-packages-partial.out" does not include all the
# required files for the inner loop installation.
# The full new packages list ('pip-new-packages.out') will be generated after
# all the package .whl and dependencies are downloaded (via pip download).
diff pip-pre-installed.out pip-post-installed.out \
| grep '>' \
| awk '{print $2}' > pip-new-packages-partial.out
