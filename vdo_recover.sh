#!/bin/bash -x

# Usage: ./vdo_recover.sh /dev/mapper/vdo0

# Argument:

VDO_VOLUME=$1
#MOUNT_POINT=$2

_recoveryProcess(){

# Recovery process

  VDO_SECTORS=$(dmsetup table $VDO_DEVICE | awk '{print $2}')

  truncate -s 10G /tmp/$VDO_DEVICE-tmp_loopback_file 

  LOOPBACK=$(losetup -f /tmp/$VDO_DEVICE-tmp_loopback_file --show)

  dmsetup create $VDO_DEVICE-origin --table "0 $VDO_SECTORS snapshot-origin /dev/mapper/$VDO_DEVICE"

  dmsetup create $VDO_DEVICE-snap --table "0 $VDO_SECTORS snapshot /dev/mapper/$VDO_DEVICE /dev/loop0 PO 4096 2 discard_zeroes_cow discard_passdown_origin"

# Temporary directory function
  _tmpMountPoint

  mount /dev/mapper/$VDO_DEVICE-snap $MOUNT_POINT

  fstrim $MOUNT_POINT

  vdostats $VDO_DEVICE

  dmsetup status $VDO_DEVICE-snap # Put check to see if <number of sectors used> doesn't reach the same as <total number of sectors available>.

  umount $MOUNT_POINT

# Restoring original stack

  dmsetup remove $VDO_DEVICE-origin

  dmsetup suspend $VDO_DEVICE-snap

  dmsetup create $VDO_DEVICE-merge --table "0 $VDO_SECTORS snapshot-merge /dev/mapper/$VDO_DEVICE /dev/loop0 PO 4096"

  dmsetup status $VDO_DEVICE-merge # Monitor the merge. numerator of the second-to-last field and the last field are equal (i.e. "8192/29438239823 8192").

  dmsetup remove $VDO_DEVICE-merge

  dmsetup remove $VDO_DEVICE-snap

  losetup  -d $LOOPBACK

  rm -f /tmp/$VDO_DEVICE-tmp_loopback_file

  echo "Recovery process completed."
  echo "Warning: Extend underlying disk"
}

_tmpMountPoint(){

  TMPDIR=/tmp
  timestamp=`date +%Y-%m-%d_%H:%M:%S`
  mkdir -p $TMPDIR/vdo-recover-$timestamp
  MOUNT_POINT=$TMPDIR/vdo-recover-$timestamp

}

_checkVDO(){

VDO_LIST=$(vdo list)

VDO_DEVICE=$(echo $VDO_VOLUME | awk -F "/" '{print $4}')
}

# Check if argument passed or not

#if [ -z $1 ] || [ -z $2 ]; then
if [ -z $1 ]; then
	echo "Usage: bash vdo_recover.sh <vdo device> <mount-point>"
else
  # Check if script is run by root user

  if [[ $EUID -ne 0 ]]; then
    echo "$0: cannot open $VDO_DEVICE: Permission denied" 1>&2
    exit 1
  else
    # Check for valid VDO volume
    _checkVDO

    for entry in $VDO_LIST;
    do
            if [ ${entry[@]} = $VDO_DEVICE ]; then

                  # Check if mount-point directory exist
#                  if [[ -d $MOUNT_POINT ]]; then

                        # Checking if filesystem is mounted or not
                        if grep -qs "$VDO_VOLUME" /proc/mounts; then
                          echo "$VDO_VOLUME is mounted."
                        else
                          echo "It's not mounted, recovery process started"
                          # Recovery function
                          _recoveryProcess
                        fi
#                  else
#                          echo "No such file or directory"
#                  fi
            else
                    echo "$VDO_DEVICE not present"
            fi
    done
  fi
fi
