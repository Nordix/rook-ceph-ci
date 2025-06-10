#!/bin/bash

# Ceph Disk Cleanup Script
# Usage: sudo ./disk_cleanup.sh /dev/sdb

set -euo pipefail

DEVICE="${1:-}"

# Step 0: Validate input
if [[ -z "$DEVICE" || ! -b "$DEVICE" ]]; then
    echo "❌ Error: No valid block device given."
    echo "Usage: $0 /dev/sdX"
    exit 1
fi

echo "🔍 Cleaning Ceph OSD disk: $DEVICE"

# Step 1: Unmap any crypt devices under this disk
echo "📦 Checking for crypt devices..."
lsblk -ln -o NAME "$DEVICE" | tail -n +2 | while read -r child; do
    if [[ -e "/dev/mapper/$child" ]]; then
        echo "🗝️ Closing crypt device: $child"
        sudo cryptsetup luksClose "$child" 2>/dev/null || true
        sudo dmsetup remove -f "$child" 2>/dev/null || true
    fi
done

# Step 2: Unmap any LVM/dmsetup mappings
echo "🧩 Checking for LVM/dmsetup mappings..."
MAPPERS=$(lsblk -ln -o NAME "$DEVICE" | tail -n +2)

for mapper in $MAPPERS; do
    if [[ -e "/dev/mapper/$mapper" ]]; then
        echo "🧹 Removing LVM or dmsetup mapping: $mapper"
        sudo dmsetup remove -f "$mapper" || true
    fi
done

# Step 3: Wipe signatures
echo "🧽 Wiping filesystem and partition table signatures..."
sudo wipefs -a "$DEVICE"

# Final check
echo "🔍 Final state:"
lsblk "$DEVICE"

echo "✅ Disk $DEVICE cleanup complete."
