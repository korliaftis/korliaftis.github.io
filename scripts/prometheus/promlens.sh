#!/bin/bash

# This script installs Promlens on Debian based systems.

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

# promlens variables
PROMLENS_SA="promlens"
PROMLENS_VERSION="$(curl -s https://api.github.com/repos/prometheus/promlens/releases/latest | jq -r .tag_name)"
PROMLENS_VERSION_SHORT="${PROMLENS_VERSION#v}"

# promlens upgrade variables
PROMLENS_UPGRADE=false
if [ -f /usr/local/bin/promlens ]; then
    PROMLENS_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading promlens ${PROMLENS_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/promlens-${PROMLENS_VERSION_SHORT}.linux-${SYSTEM_ARCH}.tar.gz https://github.com/prometheus/promlens/releases/download/${PROMLENS_VERSION}/promlens-${PROMLENS_VERSION_SHORT}.linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/promlens-${PROMLENS_VERSION_SHORT}.linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${PROMLENS_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop promlens.service

    # copy binaries
    cp ${TEMP_DIR}/promlens-${PROMLENS_VERSION_SHORT}.linux-${SYSTEM_ARCH}/promlens /usr/local/bin/promlens

    # update ownership
    chown ${PROMLENS_SA}:${PROMLENS_SA} /usr/local/bin/promlens

    # start service
    systemctl --quiet start promlens.service

    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrade succeeded"

    exit 0
fi

### install

# status message
echo -e "\033[0;92mINFO:\033[0m starting the installation"

# create service account
useradd --system --no-create-home --shell /bin/false ${PROMLENS_SA}

# copy binaries
cp ${TEMP_DIR}/promlens-${PROMLENS_VERSION_SHORT}.linux-${SYSTEM_ARCH}/promlens /usr/local/bin/promlens

# update ownership
chown ${PROMLENS_SA}:${PROMLENS_SA} /usr/local/bin/promlens

# create service
cat << EOF > /etc/systemd/system/promlens.service
[Unit]
Description=PromLens
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${PROMLENS_SA}
Group=${PROMLENS_SA}
ExecStart=/usr/local/bin/promlens \
--web.default-prometheus-url="https://demo.promlabs.com" \
--log.level="info" \
--log.format="logfmt" \
--web.listen-address=":9096"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start promlens.service
systemctl --quiet enable promlens.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
