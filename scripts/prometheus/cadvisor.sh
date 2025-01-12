#!/bin/bash

# This script installs cAdvisor on Debian based systems.

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
PACKAGES=("curl" "jq")

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

# cadvisor variables
CADVISOR_VERSION="$(curl -s https://api.github.com/repos/google/cadvisor/releases/latest | jq -r .tag_name)"

# cadvisor upgrade variables
CADVISOR_UPGRADE=false
if [ -f /usr/local/bin/cadvisor ]; then
    CADVISOR_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading cadvisor ${CADVISOR_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/cadvisor-${CADVISOR_VERSION}-linux-${SYSTEM_ARCH} https://github.com/google/cadvisor/releases/download/${CADVISOR_VERSION}/cadvisor-${CADVISOR_VERSION}-linux-${SYSTEM_ARCH}

### upgrade

if [ "${CADVISOR_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop cadvisor.service

    # copy binaries
    cp ${TEMP_DIR}/cadvisor-${CADVISOR_VERSION}-linux-${SYSTEM_ARCH} /usr/local/bin/cadvisor

    # update permissions
    chmod +x /usr/local/bin/cadvisor

    # start service
    systemctl --quiet start cadvisor.service

    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrade succeeded"

    exit 0
fi

### install

# status message
echo -e "\033[0;92mINFO:\033[0m starting the installation"

# copy binaries
cp ${TEMP_DIR}/cadvisor-${CADVISOR_VERSION}-linux-${SYSTEM_ARCH} /usr/local/bin/cadvisor

# update permissions
chmod +x /usr/local/bin/cadvisor

# create service
cat << EOF > /etc/systemd/system/cadvisor.service
[Unit]
Description=cAdvisor
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=root
Group=root
ExecStart=/usr/local/bin/cadvisor \
--docker_only=true \
--housekeeping_interval="10s" \
--listen_ip="0.0.0.0" \
--port="9324"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start cadvisor.service
systemctl --quiet enable cadvisor.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
