#!/bin/bash

# This script generates a Kubernetes YAML manifest for deploying a basic web application which can be used to test and troubleshoot routing and ingress configurations.

set -e
set -u
set -o pipefail

### variables

NAME="" # a name for the app - "asdf"
DOMAIN="" # your domain name - "domain.xyz"

### preflight checks

PREFLIGHT_CHECKS_FAIL=false

if [[ -z "${NAME}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m NAME is not set"
fi

if [[ -z "${DOMAIN}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m DOMAIN is not set"
fi

if [ "${PREFLIGHT_CHECKS_FAIL}" = true ]; then
    exit 1
fi

### manifest generation

cat << EOF > ${NAME}.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAME}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  namespace: ${NAME}
  labels:
    app: ${NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      containers:
      - name: app
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
  namespace: ${NAME}
  labels:
    app: ${NAME}
spec:
  selector:
    app: ${NAME}
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${NAME}
  namespace: ${NAME}
  labels:
    app: ${NAME}
spec:
  rules:
  - host: ${NAME}.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${NAME}
            port:
              number: 80
EOF

echo -e "\033[0;92m${PWD}/${NAME}.yaml\033[0m"
