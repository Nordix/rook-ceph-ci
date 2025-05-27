#! /usr/bin/env bash
set -eux

VARS_FILE="${1}"

# shellcheck disable=SC1090
source "${VARS_FILE}"

export CEPH_IMAGE

cd "/home/${USER}"

echo "Installin minikube"
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64


echo "Install kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo "Install yq"
curl -L https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -o yq
chmod +x yq
sudo mv yq /usr/local/bin/yq

echo "Fetching latest Go 1.24.x release..."
GO_VERSION=1.24.3
echo "Installing Go version: $GO_VERSION"

CURRENT_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')

if [ -n "${CURRENT_GO_VERSION+x}" ]; then
  echo "Currently installed Go version: $CURRENT_GO_VERSION"
fi

if [ "${CURRENT_GO_VERSION:-}" = "$GO_VERSION" ]; then
    echo "Go $GO_VERSION is already installed."
else
    echo "Installing Go $GO_VERSION..."
    curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    echo "export PATH=/usr/local/go/bin:$PATH" >> $HOME/.profile
    export PATH=/usr/local/go/bin:$PATH
fi

go version

echo "Cloning Rook repo"
git clone "https://github.com/rook/rook.git" rook
cd rook

echo "Setup minikube cluster"

export PATH=/usr/local/go/bin:$PATH
tests/scripts/github-action-helper.sh install_minikube_with_none_driver v1.32.0 || true
tests/scripts/github-action-helper.sh install_deps
tests/scripts/github-action-helper.sh print_k8s_cluster_status
tests/scripts/github-action-helper.sh build_rook

echo "Validate yaml"

tests/scripts/github-action-helper.sh validate_yaml

echo "Cluster Setup"

tests/scripts/github-action-helper.sh use_local_disk
tests/scripts/github-action-helper.sh create_partitions_for_osds
tests/scripts/github-action-helper.sh deploy_cluster
tests/scripts/github-action-helper.sh deploy_all_additional_resources_on_cluster

echo "Setup CSI Addons"
tests/scripts/csiaddons.sh setup_csiaddons

echo "Wait for Ceph"
tests/scripts/github-action-helper.sh wait_for_prepare_pod 2
tests/scripts/github-action-helper.sh wait_for_ceph_to_be_ready all 2

echo "Ceph Mgr Ready Check"

set -euxo pipefail

mkdir tmp
cd tmp

# Get and export the toolbox pod name
export toolbox=$(kubectl get pod -l app=rook-ceph-tools -n rook-ceph -o jsonpath='{.items[0].metadata.name}')
if [ -z "$toolbox" ]; then
echo "ERROR: rook-ceph-tools pod not found."
exit 1
fi

# Wait for ceph mgr to expose its IP
mgr_raw

# Get the IP and wait for Prometheus exporter
export mgr_raw=$(kubectl -n rook-ceph exec "$toolbox" -- ceph mgr dump -f json | jq --raw-output .active_addr)
export mgr_ip=${mgr_raw%%:*}

timeout 60 sh -c "
until kubectl -n rook-ceph exec \"$toolbox\" -- curl --silent --show-error \"$mgr_ip:9283\"; do
    echo \"Waiting for prometheus exporter...\"
    sleep 1
done
"

cd /tmp/../rook

echo "Log collection"

pwd
LOGS_TARBALL="logs-${BUILD_TAG}.tgz"
tests/scripts/collect-logs.sh
tar -cvzf "${LOGS_TARBALL}" tmp/*
