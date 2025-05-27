#! /usr/bin/env bash

# Global defines for Airship CI infrastructure
# ============================================

export OS_AUTH_URL=https://xerces.ericsson.net:5000
export OS_PROJECT_ID=b62dc8622f87407589de9f7dcec13d25
export OS_PROJECT_NAME="EST_Metal3_CI"
export OS_USER_DOMAIN_NAME="xerces"
export OS_PROJECT_DOMAIN_ID="99882e968d0b44308e7ac01e78af2163"
export OS_REGION_NAME="RegionOne"
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME="RegionOne"
# Description:

get_subnet_name() {
  echo "${1:?}-subnet"
}

# Description:
# Waits for SSH connection to come up for a server
#
# Usage:
#   wait_for_ssh <ssh_user> <ssh_key_path> <server>
#
wait_for_ssh() {
  local USER KEY SERVER

  USER="${1:?}"
  KEY="${2:?}"
  SERVER="${3:?}"

  echo "Waiting for SSH connection to Host[${SERVER}]"
  until ssh -o ConnectTimeout=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${KEY}" \
    "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1
        do sleep 1
  done

  echo "SSH connection to host[${SERVER}] is up."
}

# Description:
# Check that cloud-init completed successfully.
#
# Usage:
#   vm_healthy <ssh_user> <ssh_key_path> <server>
vm_healthy() {
  local USER KEY SERVER

  USER="${1:?}"
  KEY="${2:?}"
  SERVER="${3:?}"

  cloud_init_status=$(ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "${KEY}" \
    "${USER}"@"${SERVER}" cloud-init status --long --wait)
  if echo "${cloud_init_status}" | grep "error"; then
    echo "There was a cloud-init error:"
    echo "${cloud_init_status}"
    return 1
  else
    echo "Cloud-init completed successfully!"
    return 0
  fi
}
