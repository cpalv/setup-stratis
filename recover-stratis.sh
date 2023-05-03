#!/bin/bash
set -e

[ $EUID -ne 0 ] && echo "admin access required to recover stratis pool" && exit 1

# Install stratis for live environment
dnf install stratisd stratisd-dracut stratis-cli -y
systemctl start stratisd


read -p "Keyname: " keyname
echo
stratis key set --capture-key $keyname

read -p "Poolname: " poolname
echo
stratis pool start --unlock-method keyring --name $poolname

recover_root=/recover
mkdir -p $recover_root

# GOTCHA:  Assumes there is only 1 stratis filesystem per pool
pool_fs=$(stratis fs | grep "$poolname" | awk '{print $15}')

mount $pool_fs $recover_root
mount --types proc /proc $recover_root/proc
mount --rbind /sys $recover_root/sys
mount --make-rslave $recover_root/sys
mount --rbind /dev $recover_root/dev
mount --make-rslave $recover_root/dev
mount --bind /run $recover_root/run
mount --make-slave $recover_root/run
mount -t tmpfs /tmp $recover_root/tmp  -o mode=1777,strictatime,nodev,nosuid


echo "Good luck!"
chroot "$recover_root"
