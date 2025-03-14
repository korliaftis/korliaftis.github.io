#!/bin/bash

# This script installs karma on Debian based systems.

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
APP_SA="karma"
APP_VERSION="$(curl -s https://api.github.com/repos/prymitive/karma/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/karma ]; then
    APP_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading karma ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/karma-linux-${SYSTEM_ARCH}.tar.gz https://github.com/prymitive/karma/releases/download/${APP_VERSION}/karma-linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/karma-linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop karma.service

    # copy binaries
    cp ${TEMP_DIR}/karma-linux-${SYSTEM_ARCH} /usr/local/bin/karma

    # update ownership
    chown ${APP_SA}:${APP_SA} /usr/local/bin/karma

    # start service
    systemctl --quiet start karma.service

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
cp ${TEMP_DIR}/karma-linux-${SYSTEM_ARCH} /usr/local/bin/karma

# update ownership
chown ${APP_SA}:${APP_SA} /usr/local/bin/karma

# create service
cat << EOF > /etc/systemd/system/karma.service
[Unit]
Description=Karma
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${APP_SA}
Group=${APP_SA}
ExecStart=/usr/local/bin/karma \
--alertAcknowledgement.enabled=false \
--alertmanager.interval="5s" \
--alertmanager.proxy=true \
--alertmanager.name="alertmanager" \
--alertmanager.readonly=false \
--alertmanager.timeout="10s" \
--alertmanager.uri="http://localhost:9093" \
--history.enabled=true \
--karma.name="karma" \
--listen.port="9095" \
--log.format="text" \
--log.level="info"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start karma.service
systemctl --quiet enable karma.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
