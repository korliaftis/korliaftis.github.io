#!/bin/bash

# This script generates a wildcard certificate for a domain using acme.sh and the Cloudflare API.

set -e
set -u
set -o pipefail

### variables

USERNAME=""    # your debian username - "user"
DOMAIN_NAME="" # your domain name - "domain.xyz"
API_TOKEN=""   # your cloudflare api token - "6_z3K2aFdSpIq6VBkaz3i4xHT_uYiBNmDftWNZ-K"

TEMP_DIR="$(mktemp -d)"

### preflight checks

PREFLIGHT_CHECKS_FAIL="false"

if [[ "${EUID}" -ne 0 ]]; then
    echo -e "\033[0;91mERROR:\033[0m script not running as root"
    exit 1
fi

if ! command -v docker > /dev/null 2>&1; then
    PREFLIGHT_CHECKS_FAIL="true"
    echo -e "\033[0;91mERROR\033[0m docker is not installed"
fi

VARIABLES=(
    USERNAME
    DOMAIN_NAME
    API_TOKEN
)

for i in "${VARIABLES[@]}"; do
    if [[ -z "${!i}" ]]; then
        PREFLIGHT_CHECKS_FAIL="true"
        echo -e "\033[0;91mERROR\033[0m variable is not set: ${i}"
    fi
done

if [[ "${PREFLIGHT_CHECKS_FAIL}" == "true" ]]; then
    exit 1
fi

### acme.sh

for i in {5..1}; do
  echo -e "\033[0;95m$i\033[0m"
  sleep 1
done

docker run \
  --rm \
  --interactive \
  --tty \
  --env CF_Token="${API_TOKEN}" \
  --volume ${TEMP_DIR}/tls:/acme.sh \
  neilpang/acme.sh:latest \
  acme.sh \
  --dns dns_cf \
  --domain ${DOMAIN_NAME} \
  --domain *.${DOMAIN_NAME} \
  --domain *.local.${DOMAIN_NAME} \
  --issue \
  --keylength 4096 \
  --server letsencrypt

install -d -m 0775 -o ${USERNAME} -g ${USERNAME} /home/${USERNAME}/.tls
cp -r ${TEMP_DIR}/tls/${DOMAIN_NAME}/* /home/${USERNAME}/.tls
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.tls/*
