#! /usr/bin/env bash
set -eux

VARS_FILE="${1}"

# shellcheck disable=SC1090
source "${VARS_FILE}"

export CEPH_IMAGE

cd "/home/${USER}"
git clone "https://github.com/rook/rook.git" rook

cd rook
