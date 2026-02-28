#!/bin/bash

# This script installs Node Exporter on Debian based systems.

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

# app variables
APP_SA="node_exporter"
APP_VERSION="$(curl -Ls https://api.github.com/repos/prometheus/node_exporter/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/node_exporter ]; then
    APP_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading node exporter ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/node_exporter-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz https://github.com/prometheus/node_exporter/releases/download/${APP_VERSION}/node_exporter-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/node_exporter-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop node_exporter.service

    # copy binaries
    install -m 0755 -o ${APP_SA} -g ${APP_SA} ${TEMP_DIR}/node_exporter-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/node_exporter /usr/local/bin/node_exporter

    # start service
    systemctl --quiet start node_exporter.service

    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrade succeeded"

    exit 0
fi

### install

# status message
echo -e "\033[0;92mINFO:\033[0m starting the installation"

# create service account
useradd --system --no-create-home --shell /bin/false ${APP_SA}

# copy binaries
install -m 0755 -o ${APP_SA} -g ${APP_SA} ${TEMP_DIR}/node_exporter-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/node_exporter /usr/local/bin/node_exporter

# create service
cat << EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${APP_SA}
Group=${APP_SA}
ExecStart=/usr/local/bin/node_exporter \
--web.telemetry-path="/metrics" \
--web.listen-address="0.0.0.0:9100" \
--log.level="info" \
--log.format="logfmt"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start node_exporter.service
systemctl --quiet enable node_exporter.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
