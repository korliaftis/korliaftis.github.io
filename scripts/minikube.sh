#!/bin/bash

# This script sets up a Kubernetes environment with Traefik, Prometheus and Argo CD.

set -e
set -u
set -o pipefail

### variables

DOMAIN_NAME=""          # your domain name - "domain.xyz"
GITHUB_USERNAME=""      # your github username - "user"
GITHUB_REPOSITORY=""    # your github repository name - "argocd"
MINIKUBE_NODES=""       # the number of minikube nodes - "3"
TLS_PUBLIC_KEY_PATH=""  # the full path to the tls public key - "/home/user/.tls/fullchain.cer"
TLS_PRIVATE_KEY_PATH="" # the full path to the tls private key - "/home/user/.tls/domain.xyz.key"
SSH_PRIVATE_KEY_PATH="" # the full path to the ssh private key - "/home/user/.ssh/id_ed25519"

### preflight checks

PREFLIGHT_CHECKS_FAIL="false"

if [[ "${EUID}" -eq 0 ]]; then
    echo -e "\033[0;91mERROR:\033[0m script running as root"
    exit 1
fi

if ! id -nG | grep -qw docker; then
    echo -e "\033[0;91mERROR:\033[0m user must be in the docker group"
    exit 1
fi

BINARIES=(
    docker
    minikube
    terraform
    helm
)

for i in "${BINARIES[@]}"; do
    if ! command -v "${i}" > /dev/null 2>&1; then
        PREFLIGHT_CHECKS_FAIL="true"
        echo -e "\033[0;91mERROR:\033[0m dependency is not installed: ${i}"
    fi
done

VARIABLES=(
    DOMAIN_NAME
    GITHUB_USERNAME
    GITHUB_REPOSITORY
    MINIKUBE_NODES
    TLS_PUBLIC_KEY_PATH
    TLS_PRIVATE_KEY_PATH
    SSH_PRIVATE_KEY_PATH
)

for i in "${VARIABLES[@]}"; do
    if [[ -z "${!i}" ]]; then
        PREFLIGHT_CHECKS_FAIL="true"
        echo -e "\033[0;91mERROR\033[0m variable is not set: ${i}"
    fi
done

FILES=(
    TLS_PUBLIC_KEY_PATH
    TLS_PRIVATE_KEY_PATH
    SSH_PRIVATE_KEY_PATH
)

for i in "${FILES[@]}"; do
    VALUE="${!i}"
    if [[ -n "${VALUE}" && ! -f "${VALUE}" ]]; then
        PREFLIGHT_CHECKS_FAIL="true"
        echo -e "\033[0;91mERROR\033[0m file does not exist: ${VALUE}"
    fi
done

if [[ -n "${MINIKUBE_NODES}" ]]; then
    if ! [[ "${MINIKUBE_NODES}" =~ ^[0-9]+$ ]]; then
        PREFLIGHT_CHECKS_FAIL="true"
        echo -e "\033[0;91mERROR\033[0m variable MINIKUBE_NODES must be an integer"
    elif (( MINIKUBE_NODES < 2 )); then
        echo -e "\033[0;93mWARNING\033[0m variable MINIKUBE_NODES is set to less than 2 which will cause some pods to remain in a pending state"
    fi
fi

if [[ "${PREFLIGHT_CHECKS_FAIL}" == "true" ]]; then
    exit 1
fi

### environment reset

for i in {5..1}; do
  echo -e "\033[0;96m$i\033[0m"
  sleep 1
done

if [[ -d "${HOME}/minikube" ]]; then
    rm -rf "${HOME}/minikube"
fi

mkdir ${HOME}/minikube
mkdir ${HOME}/minikube/values
cd ${HOME}/minikube

### helm values

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

prometheusOperator:
  kubeletEndpointsEnabled: false
  kubeletEndpointSliceEnabled: true

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
    serviceDiscoveryRole: "EndpointSlice"
EOF

cat << EOF > values/argo-cd.yaml
global:
  domain: argocd.${DOMAIN_NAME}

configs:
  params:
    server.insecure: true

server:
  ingress:
    enabled: true
    ingressClassName: traefik
EOF

### terraform manifests

cat << 'EOF' > terraform.tf
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
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
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik_crds" {
  chart       = "traefik-crds"
  name        = "traefik-crds"
  namespace   = kubernetes_namespace_v1.traefik.id
  repository  = "https://traefik.github.io/charts"
  version     = "1.13.0"
  timeout     = 600
  max_history = 10
}

resource "helm_release" "traefik" {
  chart       = "traefik"
  name        = "traefik"
  namespace   = kubernetes_namespace_v1.traefik.id
  repository  = "https://traefik.github.io/charts"
  values      = [file("values/traefik.yaml")]
  version     = "38.0.1"
  timeout     = 600
  max_history = 10
}

resource "kubernetes_secret_v1" "default_tls" {
  metadata {
    name      = "default-tls"
    namespace = kubernetes_namespace_v1.traefik.id
  }
  data = {
    "tls.crt" = file("${TLS_PUBLIC_KEY_PATH}")
    "tls.key" = file("${TLS_PRIVATE_KEY_PATH}")
  }
  type = "kubernetes.io/tls"
}
EOF

cat << 'EOF' > kube-prometheus-stack.tf
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "prometheus_operator_crds" {
  chart       = "prometheus-operator-crds"
  name        = "prometheus-operator-crds"
  namespace   = kubernetes_namespace_v1.monitoring.id
  repository  = "https://prometheus-community.github.io/helm-charts"
  version     = "25.0.1"
  timeout     = 600
  max_history = 10
}

resource "helm_release" "kube_prometheus_stack" {
  chart       = "kube-prometheus-stack"
  name        = "kube-prometheus-stack"
  namespace   = kubernetes_namespace_v1.monitoring.id
  repository  = "https://prometheus-community.github.io/helm-charts"
  values      = [file("values/kube-prometheus-stack.yaml")]
  version     = "80.12.0"
  timeout     = 600
  max_history = 10
}
EOF

cat << EOF > argo-cd.tf
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  chart       = "argo-cd"
  name        = "argo-cd"
  namespace   = kubernetes_namespace_v1.argocd.id
  repository  = "https://argoproj.github.io/argo-helm"
  values      = [file("values/argo-cd.yaml")]
  version     = "9.2.4"
  timeout     = 600
  max_history = 10
}

resource "kubernetes_secret_v1" "github" {
  metadata {
    name      = "github"
    namespace = kubernetes_namespace_v1.argocd.id
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url           = "ssh://git@github.com/${GITHUB_USERNAME}/${GITHUB_REPOSITORY}.git"
    sshPrivateKey = file("${SSH_PRIVATE_KEY_PATH}")
  }
  type = "Opaque"
}
EOF

### environment setup

minikube delete && minikube start --driver="docker" --nodes="${MINIKUBE_NODES}" --addons="metrics-server"

terraform init

terraform apply -auto-approve \
  -target="helm_release.traefik_crds" \
  -target="helm_release.prometheus_operator_crds"

terraform apply -auto-approve

### outputs

echo -e "\033[0;96mINFO\033[0m the password for ArgoCD is: $(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode && echo)"
