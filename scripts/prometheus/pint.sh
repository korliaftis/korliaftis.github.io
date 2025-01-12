#!/bin/bash

# This script installs pint on Debian based systems.

set -e
set -u
set -o pipefail

### preflight checks

# failure indicator
PREFLIGHT_CHECKS_FAIL=false

# user check
if [ "${EUID}" -ne 0 ]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR:\033[0m not running as root"
fi

# dependency check
PACKAGES=("curl" "tar" "jq")

for i in "${PACKAGES[@]}"; do
    if ! command -v "${i}" >/dev/null 2>&1; then
        PREFLIGHT_CHECKS_FAIL=true
        echo -e "\033[0;91mERROR:\033[0m ${i} is not installed"
    fi
done

# failure indicator check
if [ "${PREFLIGHT_CHECKS_FAIL}" = true ]; then
    exit 1
fi

### variables

# script variables
TEMP_DIR="$(mktemp -d)"
SYSTEM_ARCH="$(dpkg --print-architecture)"

# pint variables
PINT_VERSION="$(curl -s https://api.github.com/repos/cloudflare/pint/releases/latest | jq -r .tag_name)"
PINT_VERSION_SHORT="${PINT_VERSION#v}"

# pint upgrade variables
PINT_UPGRADE=false
if [ -f /usr/local/bin/pint ]; then
    PINT_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading pint ${PINT_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/pint-${PINT_VERSION}-linux-${SYSTEM_ARCH}.tar.gz https://github.com/cloudflare/pint/releases/download/${PINT_VERSION}/pint-${PINT_VERSION_SHORT}-linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/pint-${PINT_VERSION}-linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${PINT_UPGRADE}" = true ]; then
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
