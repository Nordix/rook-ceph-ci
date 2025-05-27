#!/usr/bin/env bash

set -eu


CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
TEST_EXECUTER_FIP_TAG="${TEST_EXECUTER_FIP_TAG:-${TEST_EXECUTER_VM_NAME}-floating-ip}"

echo "Running in region: $OS_REGION_NAME"

if [[ "$OS_REGION_NAME" != "Kna1" ]]
then
  # Find executer floating ip
  TEST_EXECUTER_FIP_ID="$(openstack floating ip list --tags "${TEST_EXECUTER_FIP_TAG}" -f value -c ID)"

  # Delete executer floating ip
  echo "Deleting executer floating IP ${TEST_EXECUTER_FIP_ID}."
  echo "${TEST_EXECUTER_FIP_ID}" | xargs openstack floating ip delete
  echo "Executer floating IP ${TEST_EXECUTER_FIP_ID} is deleted."

  # Check and delete orphaned floating IPs
  openstack floating ip list --status "DOWN" --column "ID" -f json | jq --raw-output '.[]."ID"' | xargs -0 openstack floating ip delete || true
fi

# Delete executer vm
echo "Deleting executer VM ${TEST_EXECUTER_VM_NAME}."
openstack server delete "${TEST_EXECUTER_VM_NAME}"
echo "Executer VM ${TEST_EXECUTER_VM_NAME} is deleted."

# Delete executer VM port
echo "Deleting executer VM port ${TEST_EXECUTER_PORT_NAME}."
openstack port delete "${TEST_EXECUTER_PORT_NAME}"
echo "Executer VM port ${TEST_EXECUTER_PORT_NAME} is deleted."
