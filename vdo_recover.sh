#!/bin/bash -x

# Usage: bash vdo_recover.sh vdo0 /mnt/vdo0

_recoveryProcess(){

  # Recovery process

  vdo_sectors=$(dmsetup table $vdo_device | awk '{print $2}')

  truncate -s 10G /tmp/$vdo_device-tmp_loopback_file 

  loopback=$(losetup -f /tmp/$vdo_device-tmp_loopback_file --show)

  dmsetup create $vdo_device-origin --table "0 $vdo_sectors snapshot-origin /dev/mapper/$vdo_device"

  dmsetup create $vdo_device-snap --table "0 $vdo_sectors snapshot /dev/mapper/$vdo_device /dev/loop0 PO 4096 2 discard_zeroes_cow discard_passdown_origin"

  mount /dev/mapper/$vdo_device-snap $mount_point

  fstrim $mount_point

  vdostats $vdo_device

  dmsetup status $vdo_device-snap # Put check to see if <number of sectors used> doesn't reach the same as <total number of sectors available>.

  umount $mount_point

  # Restoring original stack

  dmsetup remove $vdo_device-origin

  dmsetup suspend $vdo_device-snap

  dmsetup create $vdo_device-merge --table "0 $vdo_sectors snapshot-merge /dev/mapper/$vdo_device /dev/loop0 PO 4096"

  dmsetup status $vdo_device-merge # Monitor the merge. numerator of the second-to-last field and the last field are equal (i.e. "8192/29438239823 8192").

  dmsetup remove $vdo_device-merge

  dmsetup remove $vdo_device-snap

  losetup  -d $loopback

  rm -f /tmp/$vdo_device-tmp_loopback_file

  mount /dev/mapper/$vdo_device $mount_point

  if grep -qs "$mount_point" /proc/mounts; then
    echo "Recovery process completed, share is mounted."
    echo "Warning: Extend underlying disk"
  else
    echo "It's not mounted."
  fi
}

# Argument:

vdo_device=$1
mount_point=$2

# Check if argument passed or not

if [ -z $1 ] || [ -z $2 ]; then
	echo "Usage: bash vdo_recover.sh <vdo device> <mount-point>"
else
  # Check if script is run by root user

  if [[ $EUID -ne 0 ]]; then
    echo "$0: cannot open $vdo_device: Permission denied" 1>&2
    exit 100
  else
    # Check if the device is a valid VDO device

    vdo_list=$(vdo list)

    for entry in $vdo_list;
    do
            if [ ${entry[@]} = $vdo_device ]; then
                  # Check if mount-point directory exist

                  if [[ -d $mount_point ]]; then
                        # Checking if filesystem is mounted or not

                        if grep -qs "$mount_point" /proc/mounts; then
                          umount $mount_point
                          echo "It's umounted."
                        else
                          echo "It's not mounted, recovery process started"
                          # Put function name here
                          _recoveryProcess
                        fi
                  else
                          echo "No such file or directory"
                  fi
            else
                    echo "$vdo_device not present"
            fi
    done
  fi
fi