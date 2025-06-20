#!/bin/bash

# This script installs Promlens on Debian based systems.

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
APP_SA="promlens"
APP_VERSION="$(curl -s https://api.github.com/repos/prometheus/promlens/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/promlens ]; then
    APP_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading promlens ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/promlens-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz https://github.com/prometheus/promlens/releases/download/${APP_VERSION}/promlens-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/promlens-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop promlens.service

    # copy binaries
    cp ${TEMP_DIR}/promlens-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/promlens /usr/local/bin/promlens

    # update ownership
    chown ${APP_SA}:${APP_SA} /usr/local/bin/promlens

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
useradd --system --no-create-home --shell /bin/false ${APP_SA}

# copy binaries
cp ${TEMP_DIR}/promlens-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/promlens /usr/local/bin/promlens

# update ownership
chown ${APP_SA}:${APP_SA} /usr/local/bin/promlens

# create service
cat << EOF > /etc/systemd/system/promlens.service
[Unit]
Description=PromLens
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${APP_SA}
Group=${APP_SA}
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
