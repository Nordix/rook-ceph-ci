#!/bin/bash

MAX_RETRIES=15
SLEEP_SECONDS=10

# Extract proper device names sorted by indentation depth (deepest first)
mapfile -t DM_DEVICES < <(
  lsblk -rno NAME,TYPE | awk '$2 == "crypt" || $2 == "lvm" { print $1 }' | tac
)

if [ ${#DM_DEVICES[@]} -eq 0 ]; then
  echo "No device-mapper entries found. Nothing to clean."
  exit 0
fi

echo "Devices to remove (child first):"
printf ' - %s\n' "${DM_DEVICES[@]}"
echo

# Loop with retry
for dev in "${DM_DEVICES[@]}"; do
  echo "Removing $dev ..."
  sudo dmsetup remove -f "$dev";
  echo "Successfully removed $dev"
done
# Final disk cleanup
echo "Wiping /dev/sdb ..."
sudo wipefs -a /dev/sdb || echo " wipefs failed"

sudo rm -rf /dev/ceph-*
sudo rm -rf /dev/mapper/ceph--*
sudo rm -rf /var/lib/rook
