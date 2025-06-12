#!/bin/bash

MAX_RETRIES=15
SLEEP_SECONDS=10

# Extract proper device names sorted by indentation depth (deepest first)
mapfile -t DM_DEVICES < <(
  sudo dmsetup ls --tree | \
  awk '
    {
      line = $0
      match(line, /^ */)
      indent = RLENGTH
      gsub(/^ *[└├│─]* */, "", line)
      split(line, parts, " ")
      if (parts[1] !~ /^\(.*\)$/)  # skip lines like (8:16)
        print indent, parts[1]
    }
  ' | sort -n | awk '{print $2}'  # ascending: children first
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
  retry=0
  while true; do
    if sudo dmsetup remove -f "$dev"; then
      echo "Successfully removed $dev"
      break
    else
      ((retry++))
      if (( retry >= MAX_RETRIES )); then
        echo "Failed to remove $dev after $MAX_RETRIES attempts."
        break
      fi
      echo "Retry $retry/$MAX_RETRIES: $dev still in use. Retrying in $SLEEP_SECONDS seconds..."
      sleep "$SLEEP_SECONDS"
    fi
  done
done
# Final disk cleanup
echo "Wiping /dev/sdb ..."
sudo wipefs -a /dev/sdb || echo " wipefs failed"

sudo rm -rf /dev/ceph-*
sudo rm -rf /dev/mapper/ceph--*
sudo rm -rf /var/lib/rook
