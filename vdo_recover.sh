#!/bin/bash -x

VDO_VOLUME=$1
MNTPT=$2

TMPDIR=/tmp

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
  losetup  -d $LOOPBACK

}

_rmSnpDir(){
  if [[ -z $MNTPT ]]; then
    rm -f $RUNDIR/$VDO_DEVICE-tmp_loopback_file
    rmdir $RUNDIR
  else
    rm -f $MNTPT/$VDO_DEVICE-tmp_loopback_file
  fi
  
}

_recoveryProcess(){

  VDO_SECTORS=$(dmsetup table $VDO_DEVICE | awk '{print $2}')

  _tmpSnapDev
  
  dmsetup create $VDO_DEVICE-origin --table "0 $VDO_SECTORS snapshot-origin /dev/mapper/$VDO_DEVICE"
  dmsetup create $VDO_DEVICE-snap --table "0 $VDO_SECTORS snapshot /dev/mapper/$VDO_DEVICE $LOOPBACK PO 4096 2 discard_zeroes_cow discard_passdown_origin"

  if [ $? -ne 0 ]; then
    dmsetup remove $VDO_DEVICE-origin
    losetup  -d $LOOPBACK
    _rmSnpDir
    exit 1
  fi

  _tmpMountPoint

  _fstrimVDO

  _mergeVDO

  _rmSnpDir

  echo "Recovery complete. Extend underlying disk"
  exit 0

}

_tmpSnapDev(){

  VDO_DISK=$(vdostats $VDO_VOLUME | awk 'NR==2 {print $2}') #1K-blocks
  LO_DEV_SIZE=$(((($VDO_DISK*5/100)/1024))) #1M-blocks
  SNAPDEV=$(($LO_DEV_SIZE*1024)) #1K-blocks

  if [[ -z $MNTPT ]]; then
          TMPFS=$(df -k /run | awk 'NR==2 {print $4}')
          if [[ TMPFS -gt SNAPDEV ]]; then
                  mkdir /run/vdo
                  RUNDIR=/run/vdo
                  truncate -s ${LO_DEV_SIZE}M $RUNDIR/$VDO_DEVICE-tmp_loopback_file
                  LOOPBACK=$(losetup -f $RUNDIR/$VDO_DEVICE-tmp_loopback_file --show)
          else
                  echo "Not enough free space for Snapshot"
                  echo "Specify a mount-point"
                  exit 1
          fi
  else
          MNTDEVSIZE=$(df -k $MNTPT | awk 'NR==2 {print $4}')
          if [[ MNTDEVSIZE -gt SNAPDEV ]]; then
                  truncate -s ${LO_DEV_SIZE}M $MNTPT/$VDO_DEVICE-tmp_loopback_file
                  LOOPBACK=$(losetup -f $MNTPT/$VDO_DEVICE-tmp_loopback_file --show)
          else
                  echo "Specified mount-point doesn't have enough free space"
                  exit 1
          fi
  fi

}

_tmpMountPoint(){

  timestamp=`date +%Y-%m-%d_%H:%M:%S`
  mkdir -p $TMPDIR/vdo-recover-$timestamp
  MOUNT_POINT=$TMPDIR/vdo-recover-$timestamp
  mount /dev/mapper/$VDO_DEVICE-snap $MOUNT_POINT

}

_checkVDO(){

  VDO_LIST=$(vdo list)

  VDO_DEVICE=$(echo $VDO_VOLUME | awk -F "/" '{print $4}')

}

if [ -z $1 ]; then
	echo "Usage: bash vdo_recover.sh <vdo device>"
  exit 1
else
  
  if [[ $EUID -ne 0 ]]; then
    echo "$0: cannot open $VDO_DEVICE: Permission denied" 1>&2
    exit 1
  else
    _checkVDO

    for entry in $VDO_LIST;
    do
            if [ ${entry[@]} = $VDO_DEVICE ]; then

                    if grep -qs "$VDO_VOLUME" /proc/mounts; then
                      echo "$VDO_VOLUME is mounted."
                      exit 1
                    else
                      echo "It's not mounted, recovery process started"
                      _recoveryProcess
                    fi
            else
                    echo "$VDO_DEVICE not present"
            fi
    done
    exit 1
  fi
fi
