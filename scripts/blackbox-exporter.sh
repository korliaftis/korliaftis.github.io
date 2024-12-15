#!/bin/bash

# This script installs the Prometheus Blackbox Exporter on Debian based x86 and ARM systems.

set -e
set -o pipefail

## variables

# script variables
TEMPDIR=$(mktemp -d)
UPGRADE=false

# blackbox exporter variables
BLACKBOX_EXPORTER_SA="blackbox_exporter"
BLACKBOX_EXPORTER_ARCH=$(dpkg --print-architecture)
BLACKBOX_EXPORTER_VERSION=$(curl -s https://raw.githubusercontent.com/prometheus/blackbox_exporter/master/VERSION)

## preflight checks

# binaries check
if ! command -v curl &> /dev/null; then
    echo -e "\033[0;91mERROR\033[0m curl is not installed!"
    exit 1
fi

if ! command -v tar &> /dev/null; then
    echo -e "\033[0;91mERROR\033[0m tar is not installed!"
    exit 1
fi

# upgrade check
if [ -f /usr/local/bin/blackbox_exporter ]; then
    UPGRADE=true
fi

## fetch binaries
curl -sLo ${TEMPDIR}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${BLACKBOX_EXPORTER_ARCH}.tar.gz https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_EXPORTER_VERSION}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${BLACKBOX_EXPORTER_ARCH}.tar.gz
tar -xzf ${TEMPDIR}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${BLACKBOX_EXPORTER_ARCH}.tar.gz --directory ${TEMPDIR}

## upgrade
if [ "$UPGRADE" = true ]; then
    # stop service
    systemctl stop blackbox_exporter.service

    # copy binaries
    cp ${TEMPDIR}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${BLACKBOX_EXPORTER_ARCH}/blackbox_exporter /usr/local/bin/

    # update permissions
    chown ${BLACKBOX_EXPORTER_SA}:${BLACKBOX_EXPORTER_SA} /usr/local/bin/blackbox_exporter

    # start service
    systemctl start blackbox_exporter.service

    exit 0
fi

## installation

# create service account
useradd --system --no-create-home --shell /bin/false ${BLACKBOX_EXPORTER_SA}

# create directories
mkdir /etc/blackbox_exporter

# copy configuration file
cp ${TEMPDIR}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${BLACKBOX_EXPORTER_ARCH}/blackbox.yml /etc/blackbox_exporter/blackbox_exporter.yaml

# copy binaries
cp ${TEMPDIR}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-${BLACKBOX_EXPORTER_ARCH}/blackbox_exporter /usr/local/bin/

# update permissions
chown ${BLACKBOX_EXPORTER_SA}:${BLACKBOX_EXPORTER_SA} /usr/local/bin/blackbox_exporter
chown -R ${BLACKBOX_EXPORTER_SA}:${BLACKBOX_EXPORTER_SA} /etc/blackbox_exporter

# create service
cat << 'EOF' > /etc/systemd/system/blackbox_exporter.service
[Unit]
Description=Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=blackbox_exporter
Group=blackbox_exporter
ExecStart=/usr/local/bin/blackbox_exporter \
--config.file=/etc/blackbox_exporter/blackbox_exporter.yaml

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl daemon-reload
systemctl enable --now blackbox_exporter.service
