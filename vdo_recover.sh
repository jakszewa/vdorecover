#!/bin/bash

#Usage: bash vdo_recovery.sh vdo0 sdb /mnt/vdo0

# Argument:

vdo_device=$1
disk=$2
mount_point=$3

# Checking if filesystem is mounted or not

if grep -qs "$mount_point" /proc/mounts; then
  umount $mount_point
  echo "It's umounted."
else
  echo "It's not mounted, recovery process started"
fi


# Recovery process

vdo_sectors=$(dmsetup table $vdo_device | awk '{print $2}')

truncate -s 10G /tmp/$vdo_device-tmp_loopback_file 

loopback=$(losetup -f /tmp/$vdo_device-tmp_loopback_file --show)

dmsetup create $vdo_device-origin --table "0 $vdo_sectors snapshot-origin /dev/mapper/$vdo_device"

dmsetup create $vdo_device-snap --table "0 $vdo_sectors snapshot /dev/mapper/$vdo_device /dev/loop0 PO 4096 2 discard_zeroes_cow discard_passdown_origin"

mount /dev/mapper/$vdo_device-snap $mount_point

fstrim $mount_point

#vdostats $vdo_device

umount $mount_point


# Restoring original stack

dmsetup remove $vdo_device-origin

dmsetup suspend $vdo_device-snap

dmsetup create $vdo_device-merge --table "0 $vdo_sectors snapshot-merge /dev/mapper/$vdo_device /dev/loop0 PO 4096"

dmsetup remove $vdo_device-merge

dmsetup remove $vdo_device-snap

losetup  -d $loopback

rm -f /tmp/$vdo_device-tmp_loopback_file

mount /dev/mapper/$vdo_device $mount_point

if grep -qs "$mount_point" /proc/mounts; then
  echo "Recovery process completed, share is mounted."
else
  echo "It's not mounted."
fi


