#!/bin/bash

# Read dmsetup tree with indentation preserved
mapfile -t DM_DEVICES < <(
  sudo dmsetup ls --tree | \
  awk '
    {
      # Count leading tree characters └, ├, │ and spaces
      match($0, /^[├└│ ]*/);
      indent = RLENGTH;
      # Output: <indent> <device>
      print indent, $1
    }
  ' | \
  sort -nr | \
  awk '{print $2}'
)

if [ ${#DM_DEVICES[@]} -eq 0 ]; then
  echo "No device-mapper entries found. Nothing to clean."
  exit 0
fi

echo "Devices to remove in order:"
printf ' - %s\n' "${DM_DEVICES[@]}"

for dev in "${DM_DEVICES[@]}"; do
  echo "Removing $dev ..."
  sudo dmsetup remove -f "$dev" || echo "⚠️  Failed to remove $dev"
done

sudo wipefs -a /dev/sdb
