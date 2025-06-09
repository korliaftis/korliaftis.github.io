#!/bin/bash

# This script installs Pushgateway on Debian based systems.

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
APP_SA="pushgateway"
APP_VERSION="$(curl -s https://api.github.com/repos/prometheus/pushgateway/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/pushgateway ]; then
    APP_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading pushgateway ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/pushgateway-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz https://github.com/prometheus/pushgateway/releases/download/${APP_VERSION}/pushgateway-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/pushgateway-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop pushgateway.service

    # copy binaries
    cp ${TEMP_DIR}/pushgateway-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/pushgateway /usr/local/bin/pushgateway

    # update ownership
    chown ${APP_SA}:${APP_SA} /usr/local/bin/pushgateway

    # start service
    systemctl --quiet start pushgateway.service

    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrade succeeded"

    exit 0
fi

### install

# status message
echo -e "\033[0;92mINFO:\033[0m starting the installation"

# create service account
useradd --system --no-create-home --shell /bin/false ${APP_SA}

# create directories
mkdir /var/lib/pushgateway

# copy binaries
cp ${TEMP_DIR}/pushgateway-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/pushgateway /usr/local/bin/pushgateway

# update ownership
chown ${APP_SA}:${APP_SA} /usr/local/bin/pushgateway
chown -R ${APP_SA}:${APP_SA} /var/lib/pushgateway

# create service
cat << EOF > /etc/systemd/system/pushgateway.service
[Unit]
Description=Pushgateway
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${APP_SA}
Group=${APP_SA}
ExecStart=/usr/local/bin/pushgateway \
--web.listen-address=":9091" \
--web.telemetry-path="/metrics" \
--web.enable-lifecycle \
--web.enable-admin-api \
--persistence.file="/var/lib/pushgateway/persistence.file" \
--persistence.interval="5m" \
--log.level="info" \
--log.format="logfmt"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start pushgateway.service
systemctl --quiet enable pushgateway.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
