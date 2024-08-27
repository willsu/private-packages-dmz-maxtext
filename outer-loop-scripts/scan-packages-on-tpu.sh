#!/bin/bash
set -exo pipefail

# Install jq
sudo apt-get install -y jq

# Scan Apt packages with pip-audit
ARCH=$(dpkg --print-architecture)
DEBCVESCAN_TAG="v0.1.31"

curl -v -L \
  https://github.com/devmatic-it/debcvescan/releases/download/${DEBCVESCAN_TAG}/debcvescan_Linux_${ARCH}.deb \
  -o debcvescan_Linux_${ARCH}.deb
sudo apt install ./debcvescan_Linux_${ARCH}.deb
debcvescan scan --format json > apt-scan-full-results.json

# Coerce the output into a string that will partially match the *.deb package names in apt-new-packages.out
# e.g. wget:1.21.2-2ubuntu1.1
touch apt-new-vuln-results.out
cat apt-scan-full-results.json \
| jq -r '.vulnerabilities[] | .package + ":" + .installed_version' \
| sed 's/\: */:/g' | uniq | sort \
| while read -r VULN_APT_PACKAGE ; do
    if grep ${VULN_APT_PACKAGE} apt-new-packages.out; then
      echo ${VULN_APT_PACKAGE} >> apt-new-vuln-results.out
    fi
  done

# Scan Python packages with pip-audit
touch pip-new-vuln-results.out
pip install pip-audit
export PATH="${PATH}:${HOME}/.local/bin"

# Hack to disable package installed by Ubuntu with invalid version number.
# This package will crash 'pip-audit', so we'll move it out of the way for the duration of the scan
# See related: https://github.com/pypa/setuptools/issues/3772 for more information
# TODO: determine if we can remove this package entirely
UBUNTU_PIP_PKG_BAD_VERSION="distro_info-1.1build1.egg-info"
if [ -e "/usr/lib/python3/dist-packages/${UBUNTU_PIP_PKG_BAD_VERSION}" ]; then
  sudo mv /usr/lib/python3/dist-packages/${UBUNTU_PIP_PKG_BAD_VERSION} .
fi

# Scan the packages using pip-audit
pip-audit --format json > pip-scan-full-results.json || true

cat pip-scan-full-results.json \
| jq -r '.dependencies[] | select(.vulns | length > 0) | '\"'(.name)==(.version)'\" \
| while read -r VULN_PIP_PACKAGE ; do
    if grep ${VULN_PIP_PACKAGE} pip-new-packages.out; then
      echo ${VULN_PIP_PACKAGE} >> pip-new-vuln-results.out
    fi
  done

# Hack to restore Ubuntu installed package after the pip-audit-scan
if [ -e "${UBUNTU_PIP_PKG_BAD_VERSION}" ]; then
  sudo mv ${UBUNTU_PIP_PKG_BAD_VERSION} /usr/lib/python3/dist-packages/
fi
