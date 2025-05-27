#!/usr/bin/env bash

set -eux


CI_DIR="$(dirname "$(readlink -f "${0}")")"
# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

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
if ! vm_healthy "${ROOK_CI_USER}" "${ROOK_CI_USER_KEY}" "${TEST_EXECUTER_IP}"; then
  echo "Server is unhealthy. Giving up."
  exit 1
fi

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
  /tmp/run_integration_tests.sh /tmp/vars.sh
