#! /bin/bash

# Starting minikube cluster
minikube start --disk-size=40g --extra-disks=1 --driver kvm2


# cloning rook repo
git clone https://github.com/rook/rook.git

# installin helm
./tests/scripts/helm.sh up.


# building  rook container image 
make build

# tagging container image
docker tag $(docker images|awk '/build-/ {print $1}') rook/ceph:local-build
docker tag rook/ceph:local-build rook/ceph:master

