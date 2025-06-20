#!/bin/bash

# This script installs pint on Debian based systems.

set -e
set -u
set -o pipefail

### preflight checks

# failure indicator
PREFLIGHT_FAIL=false

# user check
if [ "${EUID}" -ne 0 ]; then
    PREFLIGHT_FAIL=true
    echo -e "\033[0;91mERROR:\033[0m not running as root"
fi

# dependency check
PACKAGES=("curl" "jq")

for i in "${PACKAGES[@]}"; do
    if ! command -v "${i}" >/dev/null 2>&1; then
        PREFLIGHT_FAIL=true
        echo -e "\033[0;91mERROR:\033[0m ${i} is not installed"
    fi
done

# failure indicator check
if [ "${PREFLIGHT_FAIL}" = true ]; then
    exit 1
fi

### variables

# script variables
TEMP_DIR="$(mktemp -d)"
SYSTEM_ARCH="$(dpkg --print-architecture)"

# app variables
APP_VERSION="$(curl -s https://api.github.com/repos/cloudflare/pint/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/pint ]; then
    APP_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading pint ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/pint-${APP_VERSION}-linux-${SYSTEM_ARCH}.tar.gz https://github.com/cloudflare/pint/releases/download/${APP_VERSION}/pint-${APP_VERSION#v}-linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/pint-${APP_VERSION}-linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # copy binaries
    cp ${TEMP_DIR}/pint-linux-${SYSTEM_ARCH} /usr/local/bin/pint

    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrade succeeded"

    exit 0
fi

### install

# status message
echo -e "\033[0;92mINFO:\033[0m starting the installation"

# create configuration file
cat << 'EOF' > /root/.pint.hcl
prometheus "server" {
  uri = "http://localhost:9090"
}
EOF

# copy binaries
cp ${TEMP_DIR}/pint-linux-${SYSTEM_ARCH} /usr/local/bin/pint

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
