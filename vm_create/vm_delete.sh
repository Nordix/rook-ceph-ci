#!/usr/bin/env bash

set -eu
export TEST_TYPE

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
source "${CI_DIR}/utils.sh"

if [[ "${TEST_TYPE}" == "basic" ]]; then
    rm -rf venv
    python3 -m venv venv
    # shellcheck source=/dev/null
    . venv/bin/activate
    pip install python-openstackclient==7.0.0

    TEST_EXECUTER_PORT_NAME="${TEST_EXECUTER_PORT_NAME:-${TEST_EXECUTER_VM_NAME}-int-port}"
    echo "Running in region: $OS_REGION_NAME"

    # Delete executer vm
    echo "Deleting executer VM ${TEST_EXECUTER_VM_NAME}."
    openstack server delete "${TEST_EXECUTER_VM_NAME}"
    echo "Executer VM ${TEST_EXECUTER_VM_NAME} is deleted."

    # Delete executer VM port
    echo "Deleting executer VM port ${TEST_EXECUTER_PORT_NAME}."
    openstack port delete "${TEST_EXECUTER_PORT_NAME}"
    echo "Executer VM port ${TEST_EXECUTER_PORT_NAME} is deleted."
fi
