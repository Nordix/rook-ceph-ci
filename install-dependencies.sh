#!/bin/bash

set -euo pipefail

# Update system
echo "[INFO] Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install required base packages
echo "[INFO] Installing base packages..."
sudo apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release software-properties-common

# Install Docker
echo "[INFO] Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo groupadd docker
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker

# Install libvirt and required packages
echo "[INFO] Installing libvirt and related packages..."
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager

# Add current user to libvirt and docker groups
sudo usermod -aG libvirt $(USER)
sudo usermod -aG docker $(USER)

# Install kubectl
echo "[INFO] Installing kubectl..."
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Minikube
echo "[INFO] Installing Minikube..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube-linux-amd64
sudo mv minikube-linux-amd64 /usr/local/bin/minikube

# Install Go
echo "[INFO] Installing Go..."
GO_VERSION="1.22.3"
curl -LO https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz

# Set Go environment variables
echo "# Go environment" >> ~/.profile
echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.profile
echo "export GOPATH=\$HOME/go" >> ~/.profile
source ~/.profile

# Final message
echo "[INFO] Installation completed successfully!"
