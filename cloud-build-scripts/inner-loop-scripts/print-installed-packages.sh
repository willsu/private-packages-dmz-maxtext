#!/bin/bash
set -exo pipefail

# Generate the installed APT and PIP packages after inner loop maxtext installation.
# These files will be included in the Cloud Build artifacts.
dpkg-query -W -f='${Package}_${Version}_${ARCHITECTURE}.deb\n' > apt-installed.out
pip freeze > pip-installed.out
