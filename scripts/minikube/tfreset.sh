#!/bin/bash

# This script sets up a Kubernetes environment with Minikube, Traefik, Prometheus and Grafana using Terraform and Helm.

set -e
set -u
set -o pipefail

### variables

DOMAIN_NAME="" # your domain name - "domain.xyz"
CERTIFICATE_FILE_PATH="" # the full path to the certificate - "/home/${USERNAME}/.ssl/fullchain.cer"
PRIVATE_KEY_FILE_PATH="" # the full path to the private key - "/home/${USERNAME}/.ssl/${DOMAIN_NAME}.key"
MINIKUBE_NODES="3"

### preflight checks

# user check
if [ "${EUID}" -eq 0 ]; then
    echo -e "\033[0;91mERROR:\033[0m running as root"
    exit 1
fi

# failure indicator
PREFLIGHT_CHECKS_FAIL=false

# binaries check
if ! command -v minikube &> /dev/null; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m minikube is not installed"
fi

if ! command -v terraform &> /dev/null; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m terraform is not installed"
fi

if ! command -v helm &> /dev/null; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m helm is not installed"
fi

# domain variables check
if [[ -z "${DOMAIN_NAME}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m DOMAIN_NAME is not set"
fi

if [[ -z "${CERTIFICATE_FILE_PATH}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m CERTIFICATE_FILE_PATH is not set"
fi

if [[ -z "${PRIVATE_KEY_FILE_PATH}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m PRIVATE_KEY_FILE_PATH is not set"
fi

# certificate files check
if [[ -n "${CERTIFICATE_FILE_PATH}" && ! -f "${CERTIFICATE_FILE_PATH}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m certificate file at ${CERTIFICATE_FILE_PATH} does not exist"
fi

if [[ -n "${PRIVATE_KEY_FILE_PATH}" && ! -f "${PRIVATE_KEY_FILE_PATH}" ]]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR\033[0m private key file at ${PRIVATE_KEY_FILE_PATH} does not exist"
fi

# minikube variables check
if (( "${MINIKUBE_NODES}" < 2 )); then
    echo -e "\033[0;93mWARNING\033[0m MINIKUBE_NODES is set to less than 2 which will cause some pods to remain in a pending state"
fi

# failure indicator check
if [ "${PREFLIGHT_CHECKS_FAIL}" = true ]; then
    exit 1
fi

### environment reset

for i in {5..1}; do
  echo -e "\033[0;96m$i\033[0m"
  sleep 1
done

if [ ! -d "${HOME}/.project" ]; then
    mkdir "${HOME}/.project"
fi

cd "${HOME}/.project"

if [ -d "${HOME}/.project/minikube" ]; then
    rm -rf "${HOME}/.project/minikube"
fi

mkdir minikube && cd minikube

### dashboards

mkdir dashboards

curl -sLo dashboards/node-exporter-full.json https://raw.githubusercontent.com/korliaftis/korliaftis.github.io/refs/heads/master/scripts/dashboards/node-exporter-full.json
curl -sLo dashboards/traefik-kubernetes.json https://raw.githubusercontent.com/korliaftis/korliaftis.github.io/refs/heads/master/scripts/dashboards/traefik-kubernetes.json

### helm values

mkdir values

cat << EOF > values/kube-prometheus-stack.yaml
crds:
  enabled: false

defaultRules:
  disabled:
    Watchdog: true

alertmanager:
  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
    - alertmanager.${DOMAIN_NAME}
  alertmanagerSpec:
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "1000m"
        memory: "1024Mi"

grafana:
  enabled: false

kubeControllerManager:
  enabled: false

kubeEtcd:
  enabled: false

kubeScheduler:
  enabled: false

prometheus:
  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
    - prometheus.${DOMAIN_NAME}
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    retention: 30d
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "1000m"
        memory: "1024Mi"
EOF

cat << EOF > values/grafana.yaml
serviceMonitor:
  enabled: true

ingress:
  enabled: true
  ingressClassName: traefik
  hosts:
  - grafana.${DOMAIN_NAME}

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "1000m"
    memory: "1024Mi"

adminUser: admin
adminPassword: asdf12#$

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://kube-prometheus-stack-prometheus.prometheus-system.svc:9090
      access: proxy
      isDefault: true

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: "default"
      orgId: 1
      folder: ""
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/default

dashboardsConfigMaps:
  default: "dashboards"
EOF

cat << 'EOF' > values/traefik.yaml
deployment:
  replicas: 2

ingressClass:
  enabled: true
  isDefaultClass: true
  name: traefik

providers:
  kubernetesCRD:
    ingressClass: traefik
  kubernetesIngress:
    ingressClass: traefik

logs:
  access:
    enabled: true

metrics:
  prometheus:
    service:
      enabled: true
    serviceMonitor:
      enabled: true

ports:
  web:
    nodePort: 31080
    redirections:
      entryPoint:
        to: websecure
        scheme: https
  websecure:
    asDefault: true
    nodePort: 31443

tlsStore:
  default:
    defaultCertificate:
      secretName: default-tls

service:
  type: NodePort

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "1000m"
    memory: "1024Mi"

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: '{{ template "traefik.name" . }}'
          app.kubernetes.io/instance: '{{ .Release.Name }}-{{ include "traefik.namespace" . }}'
      topologyKey: kubernetes.io/hostname
EOF

### terraform manifests

cat << 'EOF' > terraform.tf
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.0-pre2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.37.1"
    }
  }
}
EOF

cat << 'EOF' > providers.tf
provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}
EOF

cat << EOF > traefik.tf
resource "kubernetes_namespace" "traefik_system" {
  metadata {
    name = "traefik-system"
  }
}

resource "helm_release" "traefik_crds" {
  chart       = "traefik-crds"
  name        = "traefik-crds"
  namespace   = kubernetes_namespace.traefik_system.id
  repository  = "https://traefik.github.io/charts"
  version     = "1.8.1"
  timeout     = 600
  max_history = 10
}

resource "helm_release" "traefik" {
  chart       = "traefik"
  name        = "traefik"
  namespace   = kubernetes_namespace.traefik_system.id
  repository  = "https://traefik.github.io/charts"
  values      = [file("values/traefik.yaml")]
  version     = "35.4.0"
  timeout     = 600
  max_history = 10
}

resource "kubernetes_secret" "default_tls" {
  metadata {
    name      = "default-tls"
    namespace = kubernetes_namespace.traefik_system.id
  }
  data = {
    "tls.crt" = file("${CERTIFICATE_FILE_PATH}")
    "tls.key" = file("${PRIVATE_KEY_FILE_PATH}")
  }
  type = "kubernetes.io/tls"
}
EOF

cat << 'EOF' > prometheus.tf
resource "kubernetes_namespace" "prometheus_system" {
  metadata {
    name = "prometheus-system"
  }
}

resource "helm_release" "prometheus_operator_crds" {
  chart       = "prometheus-operator-crds"
  name        = "prometheus-operator-crds"
  namespace   = kubernetes_namespace.prometheus_system.id
  repository  = "https://prometheus-community.github.io/helm-charts"
  version     = "20.0.1"
  timeout     = 600
  max_history = 10
}

resource "helm_release" "kube_prometheus_stack" {
  chart       = "kube-prometheus-stack"
  name        = "kube-prometheus-stack"
  namespace   = kubernetes_namespace.prometheus_system.id
  repository  = "https://prometheus-community.github.io/helm-charts"
  values      = [file("values/kube-prometheus-stack.yaml")]
  version     = "72.9.1"
  timeout     = 600
  max_history = 10
}
EOF

cat << 'EOF' > grafana.tf
resource "kubernetes_namespace" "grafana_system" {
  metadata {
    name = "grafana-system"
  }
}

resource "kubernetes_config_map" "dashboards" {
  metadata {
    name      = "dashboards"
    namespace = kubernetes_namespace.grafana_system.id
  }
  data = {
    for dashboard in fileset("${path.module}/dashboards", "*") :
    basename(dashboard) => file("${path.module}/dashboards/${dashboard}")
  }
}

resource "helm_release" "grafana" {
  chart       = "grafana"
  name        = "grafana"
  namespace   = kubernetes_namespace.grafana_system.id
  repository  = "https://grafana.github.io/helm-charts"
  values      = [file("values/grafana.yaml")]
  version     = "9.2.2"
  timeout     = 600
  max_history = 10
}
EOF

### environment setup

minikube delete && minikube start --driver="docker" --nodes="${MINIKUBE_NODES}" --addons="metrics-server"

terraform init

# first apply
terraform apply -auto-approve \
  -target="helm_release.prometheus_operator_crds" \
  -target="helm_release.traefik_crds"

# second apply
terraform apply -auto-approve
