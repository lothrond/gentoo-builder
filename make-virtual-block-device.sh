#!/bin/bash

set -o errexit

# Size of virtual block device image (in GB)
[ ${SIZE} ] || \
	SIZE=8

# Name/Directory of block device image
[ ${OUT} ] || \
	OUT=/tmp/virtual-block-device.img

# Needs root
[ ${UID} -eq 0 ] || { echo "Needs root..."; exit 1 ;}

echo "Making new blank image..."
bs=1024
count=$(( ${bs}*${SIZE}*${bs} ))
dd bs=${bs} if=/dev/zero of=${OUT} count=${count} status=progress

echo "making new block device..."
device=$(losetup -j | ${OUT} | cut -d ' ' -f 1)
losetup -fP ${device}

echo "making filesystem..."
mkfs.ext4 ${device}

echo "cleaning up..."
losetup -d ${device}

exit $?
