pipeline {
  agent { label 'ceph-rook-test' }

  environment {
    BUILD_TAG = "${env.BUILD_TAG}"
    LOG_DIR = "test"
  }

  parameters {
    string(name: 'CEPH_IMAGE', defaultValue: 'quay.io/ceph/ceph:v19', description: 'Ceph image to test with')
  }

  stages{
    stage('Install Minikube ') {
      steps {
        script {
          sh '''
            curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
            sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
          '''
        }
      }
    }
    stage('Delete Minikube if there are any') {
      steps {
        script {
          sh 'minikube delete --all'
          sh 'rm -rf rook/ || true'
        }
      }
    }
    stage('CleanUp disks') {
      steps {
        script {
          sh '''
#!/bin/bash

DISK_TO_CLEAN="/dev/vdb"

MOUNTED_PARTITIONS=$(lsblk -n -o NAME,MOUNTPOINT "$DISK_TO_CLEAN" | awk '$2 != "" {print "/dev/"$1}')

if [ -z "$MOUNTED_PARTITIONS" ]; then
    echo "[cleanup] No mounted partitions found on $DISK_TO_CLEAN. Proceeding."
else
    for p in $MOUNTED_PARTITIONS; do
        echo "[cleanup]   Unmounting $p..."
        # Try a graceful unmount, then force unmount if busy
        if ! sudo umount "$p"; then
            echo "[cleanup]   Warning: Failed graceful unmount for $p. Attempting force unmount."
            if ! sudo umount -lf "$p"; then # -l: lazy unmount, -f: force unmount
                echo "ERROR: Failed to force unmount $p. It might be heavily in use. Manual intervention required."
                echo "Please ensure $p is not mounted or in use before re-running this script."
                exit 1 # Exit if unmount fails to prevent wiping an active disk
            else
                echo "[cleanup]   $p force unmounted successfully."
            fi
        else
            echo "[cleanup]   $p unmounted successfully."
        fi
    done
fi

echo "[cleanup] Zeroing critical sectors of $DISK_TO_CLEAN to remove all lingering metadata..."
echo "[cleanup]   Zeroing first 100MB of $DISK_TO_CLEAN..."
sudo dd if=/dev/zero of="$DISK_TO_CLEAN" bs=1M count=100 oflag=direct,dsync || true

DISK_MIDDLE_SEEK_MB=$((50 * 1024)) # 50 GiB converted to MB
DISK_SIZE_BYTES=$(sudo blockdev --getsize64 "$DISK_TO_CLEAN")
DISK_SIZE_MB=$((DISK_SIZE_BYTES / (1024 * 1024)))

if [ "$DISK_SIZE_MB" -gt "$((DISK_MIDDLE_SEEK_MB + 100))" ]; then # Ensure there's space for 100MB at mid-point
    echo "[cleanup]   Zeroing 100MB around the middle of $DISK_TO_CLEAN (at ~${DISK_MIDDLE_SEEK_MB}MB)..."
    sudo dd if=/dev/zero of="$DISK_TO_CLEAN" bs=1M count=100 oflag=direct,dsync seek="$DISK_MIDDLE_SEEK_MB" || true
else
    echo "[cleanup]   Disk $DISK_TO_CLEAN too small for a mid-disk wipe (size: ${DISK_SIZE_MB}MB). Skipping."
fi

SEEK_END_MB=$((DISK_SIZE_MB - 100))
if [ "$SEEK_END_MB" -lt 0 ]; then SEEK_END_MB=0; fi
echo "[cleanup]   Zeroing last 100MB of $DISK_TO_CLEAN (starting at ~${SEEK_END_MB}MB)..."
sudo dd if=/dev/zero of="$DISK_TO_CLEAN" bs=1M count=100 oflag=direct,dsync seek="$SEEK_END_MB" || true

echo "[cleanup] Zapping disk with sgdisk to ensure a clean GPT partition table..."
if ! sudo sgdisk --zap-all "$DISK_TO_CLEAN"; then
    echo "ERROR: Failed to wipe disk $DISK_TO_CLEAN with sgdisk. This is a critical failure. Exiting."
    exit 1
fi
echo "Disk $DISK_TO_CLEAN partition table zapped successfully."

lsblk "$DISK_TO_CLEAN"

echo "Running: sudo wipefs -n $DISK_TO_CLEAN (should show no signatures)"
sudo wipefs -n "$DISK_TO_CLEAN" # Use -n for dry-run, just to inspect for any lingering signatures

sudo rm -rf /var/lib/rook || true  # Remove Rook's local state on the host
sudo rm -rf /var/lib/ceph || true  # Remove Ceph's local state on the host

# These commands are specific to NBD devices.
echo "Reloading NBD module (if applicable)..."
sudo modprobe -r nbd || true # Remove module if loaded, '|| true' prevents script from failing if not loaded
sudo modprobe nbd || true    # Load module

echo "--------------------------------------------------------"
echo "Comprehensive disk cleanup for $DISK_TO_CLEAN completed successfully."
echo "--------------------------------------------------------"
            '''
        }
      }
    }

    stage('Install kubectl and yq') {
      steps {
        script {
          sh '''
if ! command -v kubectl; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
  echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -rf kubectl
fi
if ! command -v kubectl; then
  curl -L https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -o yq
  chmod +x yq
  sudo mv yq /usr/local/bin/yq
fi
          '''
        }
      }
    }
    stage('Clone Rook Repo') {
      steps {
        sh '''
          echo "Cloning Rook repository..."
          if [ ! -d "rook" ]; then
            git clone --single-branch --branch master https://github.com/rook/rook.git
          else
            cd rook && git pull origin master
          fi
        '''
      }
    }

    stage('Install Latest Go 1.24') {
      steps {
        sh '''
          echo "Fetching latest Go 1.24.x release..."
          GO_VERSION=$(curl -s https://go.dev/dl/?mode=json | jq -r '.[].version' | grep '^go1\\.24\\.' | sort -Vr | head -n1 | sed 's/go//')
          echo "Latest Go version: $GO_VERSION"

          CURRENT_GO_VERSION=$(go version 2>/dev/null | awk \'{print $3}\' | sed \'s/go//\')
          echo "Currently installed Go version: $CURRENT_GO_VERSION"

          if [ "$CURRENT_GO_VERSION" = "$GO_VERSION" ]; then
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
        '''
      }
    }

    stage('Setup Minikube') {
      steps {
        sh '''
          cd rook/
          export PATH=/usr/local/go/bin:$PATH
          tests/scripts/github-action-helper.sh install_minikube_with_none_driver v1.32.0 || true
          tests/scripts/github-action-helper.sh install_deps
          tests/scripts/github-action-helper.sh print_k8s_cluster_status
          tests/scripts/github-action-helper.sh build_rook
          '''
      }
    }

    stage('Validate YAML') {
      steps {
        sh "rook/tests/scripts/github-action-helper.sh validate_yaml"
      }
    }
    stage('Set Ceph Version') {
      steps {
        sh "rook/tests/scripts/github-action-helper.sh replace_ceph_image rook/deploy/examples/cluster-test.yaml $CEPH_IMAGE"
      }
    }

    stage('Cluster Setup') {
      steps {
          sh '''
            cd rook/
            tests/scripts/github-action-helper.sh use_local_disk
            tests/scripts/github-action-helper.sh create_partitions_for_osds
            tests/scripts/github-action-helper.sh deploy_cluster
            tests/scripts/github-action-helper.sh deploy_all_additional_resources_on_cluster
          '''
      }
    }

    stage('Setup CSI Addons') {
      steps {
        sh "rook/tests/scripts/csiaddons.sh setup_csiaddons"
      }
    }

    stage('Wait for Ceph') {
      steps {
          sh '''
            cd rook/
            tests/scripts/github-action-helper.sh wait_for_prepare_pod 2
            tests/scripts/github-action-helper.sh wait_for_ceph_to_be_ready all 2
          '''
      }
    }

    stage('Ceph Mgr Ready Check') {
      steps {
        sh '''#!/bin/bash
          set -euxo pipefail

          cd /tmp

          # Get and export the toolbox pod name
          export toolbox=$(kubectl get pod -l app=rook-ceph-tools -n rook-ceph -o jsonpath='{.items[0].metadata.name}')
          if [ -z "$toolbox" ]; then
            echo "ERROR: rook-ceph-tools pod not found."
            exit 1
          fi

          # Wait for ceph mgr to expose its IP
          timeout 15 sh -c '
            until kubectl -n rook-ceph exec "$toolbox" -- ceph mgr dump -f json |
              jq --raw-output .active_addr |
              grep -Eqo "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"; do
              echo "Waiting for mgr IP..."
              sleep 1
            done
          '

          # Get the IP and wait for Prometheus exporter
          export mgr_raw=$(kubectl -n rook-ceph exec "$toolbox" -- ceph mgr dump -f json | jq --raw-output .active_addr)
          export mgr_ip=${mgr_raw%%:*}

          timeout 60 sh -c '
            until kubectl -n rook-ceph exec "$toolbox" -- curl --silent --show-error "$mgr_ip:9283"; do
              echo "Waiting for prometheus exporter..."
              sleep 1
            done
          '
    '''
      }
    }
  }

  post {
    always {
      echo 'Collecting logs'
      sh '''
          pwd
          LOGS_TARBALL="logs-${BUILD_TAG}.tgz"
          rook/tests/scripts/collect-logs.sh
          tar -cvzf "${LOGS_TARBALL}" test/*
      '''
      archiveArtifacts "logs-${env.BUILD_TAG}.tgz"
    }
    success {
      echo 'removing cluster'
      sh '''
      kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'
      kubectl -n rook-ceph delete cephcluster rook-ceph

      '''
      archiveArtifacts "logs-${env.BUILD_TAG}.tgz"
    }
  }
}
