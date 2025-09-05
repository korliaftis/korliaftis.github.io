#!/bin/bash

# This script generates a wildcard certificate for a domain using acme.sh and the Cloudflare API.

set -e
set -u
set -o pipefail

### variables

# script variables
USERNAME="" # your debian username - "user"
TEMP_DIR="$(mktemp -d)"

# acme.sh variables
DOMAIN_NAME=""   # your domain name - "domain.xyz"
CF_ZONE_ID=""    # your cloudflare zone id - "urjukz9cgw1y6ipv35z5hk8bp4f282rz"
CF_ACCOUNT_ID="" # your cloudflare accound id - "rb35t4w3053lofvapz0u2kwq9dwd7p5a"
CF_TOKEN=""      # your cloudflare api token - "6_z3K2aFdSpIq6VBkaz3i4xHT_uYiBNmDftWNZ-K"

### preflight checks

# failure indicator
PREFLIGHT_CHECKS_FAIL=false

# user check
if [ "${EUID}" -ne 0 ]; then
    echo -e "\033[0;91mERROR:\033[0m not running as root"
    exit 1
fi

# binaries check
if ! command -v docker &> /dev/null; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m docker is not installed"
fi

# script variables check
if [[ -z "${USERNAME}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m USERNAME is not set"
fi

# acme.sh variables check
if [[ -z "${DOMAIN_NAME}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m DOMAIN_NAME is not set"
fi

if [[ -z "${CF_ZONE_ID}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m CF_ZONE_ID is not set"
fi

if [[ -z "${CF_ACCOUNT_ID}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m CF_ACCOUNT_ID is not set"
fi

if [[ -z "${CF_TOKEN}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m CF_TOKEN is not set"
fi

# failure indicator check
if [ "${PREFLIGHT_CHECKS_FAIL}" = true ]; then
    exit 1
fi

### countdown

for i in {5..1}; do
  echo -e "\033[0;95m$i\033[0m"
  sleep 1
done

### acme.sh

docker run \
  --rm \
  --interactive \
  --tty \
  --env CF_Zone_ID="${CF_ZONE_ID}" \
  --env CF_Account_ID="${CF_ACCOUNT_ID}" \
  --env CF_Token="${CF_TOKEN}" \
  --volume ${TEMP_DIR}/ssl:/acme.sh \
  neilpang/acme.sh:latest \
  acme.sh \
  --dns dns_cf \
  --domain ${DOMAIN_NAME} \
  --domain *.${DOMAIN_NAME} \
  --issue \
  --keylength 4096 \
  --server letsencrypt

cp -r ${TEMP_DIR}/ssl/${DOMAIN_NAME}/* /home/${USERNAME}/.ssl
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssl/*
rm -rf ${TEMP_DIR}
