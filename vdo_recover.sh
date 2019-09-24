#!/bin/bash -x

# Argument:

VDO_VOLUME=$1

_fstrimVDO(){

local NUMERATOR=$(dmsetup status $VDO_DEVICE-snap | awk '{print $4}' | awk -F "/" '{print $1}')
local DENOMINATOR=$(dmsetup status $VDO_DEVICE-snap | awk '{print $4}' | awk -F "/" '{print $2}')

if [[ $NUMERATOR -lt $DENOMINATOR ]];then
        fstrim $MOUNT_POINT
        umount $MOUNT_POINT
        rmdir $MOUNT_POINT
fi

}

_mergeVDO(){

  dmsetup remove $VDO_DEVICE-origin

  dmsetup suspend $VDO_DEVICE-snap

  dmsetup create $VDO_DEVICE-merge --table "0 $VDO_SECTORS snapshot-merge /dev/mapper/$VDO_DEVICE $LOOPBACK PO 4096"

  local NUMERATOR=$(dmsetup status $VDO_DEVICE-merge | awk '{print $4}' | awk -F "/" '{print $1}')
  local DENOMINATOR=$(dmsetup status $VDO_DEVICE-merge | awk '{print $5}')

  if [[ $NUMERATOR -ne $DENOMINATOR ]];then
        read -p "Merging...." -t 10
  fi

  dmsetup remove $VDO_DEVICE-merge

  dmsetup remove $VDO_DEVICE-snap

}

_recoveryProcess(){

# Recovery process

  VDO_SECTORS=$(dmsetup table $VDO_DEVICE | awk '{print $2}')

  _tmpDevSize

  truncate -s $LO_DEV_SIZE /tmp/$VDO_DEVICE-tmp_loopback_file 
  #truncate -s 1G /tmp/$VDO_DEVICE-tmp_loopback_file 

  LOOPBACK=$(losetup -f /tmp/$VDO_DEVICE-tmp_loopback_file --show)

  dmsetup create $VDO_DEVICE-origin --table "0 $VDO_SECTORS snapshot-origin /dev/mapper/$VDO_DEVICE"

  dmsetup create $VDO_DEVICE-snap --table "0 $VDO_SECTORS snapshot /dev/mapper/$VDO_DEVICE $LOOPBACK PO 4096 2 discard_zeroes_cow discard_passdown_origin"

# Temporary directory function
  _tmpMountPoint

# FSTRIM function
  _fstrimVDO

# Restoring original stack

  _mergeVDO

  losetup  -d $LOOPBACK
  rm -f /tmp/$VDO_DEVICE-tmp_loopback_file

  echo "Recovery complete. Extend underlying disk"
  exit 0

}

_tmpDevSize(){

VDO_DISK=$(vdostats | grep $VDO_DEVICE | awk '{print $2}')

LO_DEV_SIZE=$(((($VDO_DISK*10)/100)*1024))

}

_tmpMountPoint(){

  TMPDIR=/tmp
  timestamp=`date +%Y-%m-%d_%H:%M:%S`
  mkdir -p $TMPDIR/vdo-recover-$timestamp
  MOUNT_POINT=$TMPDIR/vdo-recover-$timestamp
  mount /dev/mapper/$VDO_DEVICE-snap $MOUNT_POINT

}

_checkVDO(){

VDO_LIST=$(vdo list)

VDO_DEVICE=$(echo $VDO_VOLUME | awk -F "/" '{print $4}')

}

# Check if argument passed or not

#if [ -z $1 ] || [ -z $2 ]; then
if [ -z $1 ]; then
	echo "Usage: bash vdo_recover.sh <vdo device>"
  exit 1
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

                    # Checking if filesystem is mounted or not
                    if grep -qs "$VDO_VOLUME" /proc/mounts; then
                      echo "$VDO_VOLUME is mounted."
                      exit 1
                    else
                      echo "It's not mounted, recovery process started"
                      # Recovery function
                      _recoveryProcess
                    fi
            else
                    echo "$VDO_DEVICE not present"
                    exit 1
            fi
    done
  fi
fi
