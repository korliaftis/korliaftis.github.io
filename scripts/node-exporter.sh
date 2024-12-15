#!/bin/bash

# This script installs the Prometheus Node Exporter on Debian based x86 and ARM systems.

set -e
set -o pipefail

## variables

# script variables
TEMPDIR=$(mktemp -d)
UPGRADE=false

# node exporter variables
NODE_EXPORTER_SA="node_exporter"
NODE_EXPORTER_ARCH=$(dpkg --print-architecture)
NODE_EXPORTER_VERSION=$(curl -s https://raw.githubusercontent.com/prometheus/node_exporter/master/VERSION)

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
if [ -f /usr/local/bin/node_exporter ]; then
    UPGRADE=true
fi

## fetch binaries
curl -sLo ${TEMPDIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}.tar.gz https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}.tar.gz
tar -xzf ${TEMPDIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}.tar.gz --directory ${TEMPDIR}

## upgrade
if [ "$UPGRADE" = true ]; then
    # stop service
    systemctl stop node_exporter.service

    # copy binaries
    cp ${TEMPDIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}/node_exporter /usr/local/bin/

    # update permissions
    chown ${NODE_EXPORTER_SA}:${NODE_EXPORTER_SA} /usr/local/bin/node_exporter

    # start service
    systemctl start node_exporter.service

    exit 0
fi

## installation

# create service account
useradd --system --no-create-home --shell /bin/false ${NODE_EXPORTER_SA}

# copy binaries
cp ${TEMPDIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}/node_exporter /usr/local/bin/

# update permissions
chown ${NODE_EXPORTER_SA}:${NODE_EXPORTER_SA} /usr/local/bin/node_exporter

# create service
cat << 'EOF' > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl daemon-reload
systemctl enable --now node_exporter.service
