#!/bin/bash
set -euo pipefail
sudo dmsetup ls --target crypt --target linear || true
mapfile -t DM_DEVICES < <(sudo dmsetup ls | awk '{print $1}' | grep -E '(^q|^ceph--)' | tac)

if [ ${#DM_DEVICES[@]} -eq 0 ]; then
  echo "No matching Ceph/crypt device-mapper entries found. Nothing to clean."
  exit 0
fi

for dev in "${DM_DEVICES[@]}"; do
  sudo dmsetup remove -f "$dev" || echo "Failed to remove $dev"
done

sudo wipefs -a /dev/sdb
