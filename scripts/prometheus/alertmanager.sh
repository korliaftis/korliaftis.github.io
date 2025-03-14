#!/bin/bash

# This script installs Alertmanager on Debian based systems.

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
APP_SA="alertmanager"
APP_VERSION="$(curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/alertmanager ]; then
    APP_UPGRADE=true
fi

# app variables extended
DISCORD="${DISCORD:-"https://example.com"}"
if [ "${DISCORD}" = "https://example.com" ] && [ "${APP_UPGRADE}" = "false" ]; then
    echo -e "\033[0;93mWARNING:\033[0m no url provided for the discord receiver - a default url will be used which you can update later in /etc/alertmanager/alertmanager.yaml"
fi

HEALTHCHECKS="${HEALTHCHECKS:-"https://example.com"}"
if [ "${HEALTHCHECKS}" = "https://example.com" ] && [ "${APP_UPGRADE}" = "false" ]; then
    echo -e "\033[0;93mWARNING:\033[0m no url provided for the healthchecks receiver - a default url will be used which you can update later in /etc/alertmanager/alertmanager.yaml"
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading alertmanager ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz https://github.com/prometheus/alertmanager/releases/download/${APP_VERSION}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop alertmanager.service

    # copy binaries
    cp ${TEMP_DIR}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/alertmanager /usr/local/bin/alertmanager
    cp ${TEMP_DIR}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/amtool /usr/local/bin/amtool

    # update ownership
    chown ${APP_SA}:${APP_SA} /usr/local/bin/alertmanager
    chown ${APP_SA}:${APP_SA} /usr/local/bin/amtool

    # start service
    systemctl --quiet start alertmanager.service

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
mkdir /etc/alertmanager
mkdir /etc/alertmanager/templates
mkdir /var/lib/alertmanager

# create configuration file
cat << EOF > /etc/alertmanager/alertmanager.yaml
templates:
- "/etc/alertmanager/templates/*.tmpl"

route:
  group_by: [...]
  group_wait: 0s
  group_interval: 15s
  repeat_interval: 1d
  receiver: discord
  routes:
  - receiver: healthchecks
    group_wait: 0s
    group_interval: 15s
    repeat_interval: 15s
    matchers:
    - alertname="watchdog"

receivers:
- name: discord
  discord_configs:
  - send_resolved: true
    webhook_url: "${DISCORD}"
    title: '{{ template "discord.title" . }}'
    message: '{{ template "discord.message" . }}'
- name: healthchecks
  webhook_configs:
  - url: "${HEALTHCHECKS}"
EOF

# create template file
cat << EOF > /etc/alertmanager/templates/discord.tmpl
{{ define "discord.title" }}
{{ .CommonAnnotations.summary }}
{{ end }}

{{ define "discord.message" }}
{{ .CommonAnnotations.description }}
{{ end }}
EOF

# copy binaries
cp ${TEMP_DIR}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/alertmanager /usr/local/bin/alertmanager
cp ${TEMP_DIR}/alertmanager-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/amtool /usr/local/bin/amtool

# update ownership
chown ${APP_SA}:${APP_SA} /usr/local/bin/alertmanager
chown ${APP_SA}:${APP_SA} /usr/local/bin/amtool
chown -R ${APP_SA}:${APP_SA} /etc/alertmanager
chown -R ${APP_SA}:${APP_SA} /var/lib/alertmanager

# create service
cat << EOF > /etc/systemd/system/alertmanager.service
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${APP_SA}
Group=${APP_SA}
ExecStart=/usr/local/bin/alertmanager \
--config.file="/etc/alertmanager/alertmanager.yaml" \
--storage.path="/var/lib/alertmanager/" \
--data.retention="120h" \
--web.listen-address=":9093" \
--cluster.listen-address="" \
--log.level="info" \
--log.format="logfmt"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start alertmanager.service
systemctl --quiet enable alertmanager.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
