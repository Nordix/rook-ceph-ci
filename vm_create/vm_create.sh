#!/usr/bin/env bash

set -eux


CI_DIR="$(dirname "$(readlink -f "${0}")")"
# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

rm -rf venv
python3 -m venv venv
# shellcheck source=/dev/null
. venv/bin/activate
pip install python-openstackclient==7.0.0

export OS_AUTH_URL=https://xerces.ericsson.net:5000
export OS_PROJECT_ID=b62dc8622f87407589de9f7dcec13d25
export OS_PROJECT_NAME="EST_Metal3_CI"
export OS_USER_DOMAIN_NAME="xerces"
export OS_PROJECT_DOMAIN_ID="99882e968d0b44308e7ac01e78af2163"
export OS_REGION_NAME="RegionOne"
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME="RegionOne"

SUBNET_NAME="metal3-ci-subnet"
IMAGE_NAME="metal3-ci-ubuntu-latest"
ROOK_CI_USER="metal3ci"
TEST_EXECUTER_FLAVOR="c8m32-est"
CI_EXT_NET="metal3-ci-net"
TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
VOLUME_NAME="${TEST_EXECUTER_VM_NAME}-int-port}"
DATA_VOLUME_SIZE=20
VOLUME_TYPE="default"
TIMEOUT=300 # Timeout in seconds (e.g., 5 minutes)
INTERVAL=10

# Creating new port, needed to immediately get the ip
EXT_PORT_ID="$(openstack port create -f json \
  --network "${CI_EXT_NET}" \
  --fixed-ip subnet="$SUBNET_NAME" \
  "${TEST_EXECUTER_PORT_NAME}" | jq -r '.id')"


  # Create new executer vm
echo "Creating server ${TEST_EXECUTER_VM_NAME}"
openstack server create -f json \
  --image "${IMAGE_NAME}" \
  --flavor "${TEST_EXECUTER_FLAVOR}" \
  --port "${EXT_PORT_ID}" \
  "${TEST_EXECUTER_VM_NAME}" | jq -r '.id'

  # Get the IP
TEST_EXECUTER_IP="$(openstack port show -f json "${TEST_EXECUTER_PORT_NAME}" \
  | jq -r '.fixed_ips[0].ip_address')"

echo "Waiting for the host ${TEST_EXECUTER_VM_NAME} to come up"
# Wait for the host to come up
wait_for_ssh "${ROOK_CI_USER}" "${ROOK_CI_USER_KEY}" "${TEST_EXECUTER_IP}"

# Create a secondary volume
echo "Creating volume '${VOLUME_NAME}'..."
openstack volume create --size "$DATA_VOLUME_SIZE" \
                        --type "$VOLUME_TYPE" \
                        --bootable \
                        --read-write \
                        "$VOLUME_NAME"

# Wait for the volume to be available
echo "Waiting for volume '${VOLUME_NAME}' to become available..."

start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))

    if [[ $elapsed_time -ge $TIMEOUT ]]; then
        echo "Error: Timeout waiting for volume '${VOLUME_NAME}' to become available after ${TIMEOUT} seconds."
        openstack volume show "$VOLUME_NAME" # Show details on timeout
        exit 1
    fi

    # Get the volume status
    STATUS=$(openstack volume show -f value -c status "$VOLUME_NAME" 2>/dev/null) # Redirect stderr to dev/null

    # Check for success state
    if [[ "$STATUS" == "available" ]]; then
        echo "Volume '${VOLUME_NAME}' is now available."
        break # Exit the loop
    fi

    # Check for common failure states
    if [[ "$STATUS" == "error" || "$STATUS" == "error_deleting" || "$STATUS" == "error_restoring" || "$STATUS" == "error_extending" ]]; then
         echo "Error: Volume '${VOLUME_NAME}' entered a failure state: $STATUS"
         openstack volume show "$VOLUME_NAME" # Show details on error state
         exit 1
    fi

    # Report current status and wait if not available and not failed
    echo "Volume '${VOLUME_NAME}' status: $STATUS. Waiting..."
    sleep "$INTERVAL"
done

echo "Continuing with script execution after volume is available..."

# Attach the volume to the server
echo "Attaching volume '${VOLUME_NAME}' to server '${TEST_EXECUTER_VM_NAME}'..."
openstack server add volume "$TEST_EXECUTER_VM_NAME" "$VOLUME_NAME"

echo "Volume attached successfully."

TEMP_FILE_NAME="vars.sh"
cat <<-EOF >> "${CI_DIR}/../test_files/${TEMP_FILE_NAME}"
CEPH_IMAGE="${CEPH_IMAGE}"
EOF

scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${ROOK_CI_USER_KEY}" \
  -r "${CI_DIR}/../test_files"/ \
  "${ROOK_CI_USER}@${TEST_EXECUTER_IP}:/tmp" > /dev/null


ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=10 \
  -i "${ROOK_CI_USER_KEY}" \
  "${ROOK_CI_USER}"@"${TEST_EXECUTER_IP}" \
  /tmp/test_files/run_integration_tests.sh /tmp/test_files/vars.sh
