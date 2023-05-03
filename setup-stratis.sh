#!/bin/bash
set -e

[ $EUID -ne 0 ] && echo "admin access required for install" && exit 1

device=$1
install_root=$2
rv=$3
bkup=$4

cleanup() {
	msg=$1
	
	pids=(`lsof | grep "$install_root" | awk '{print $2}' | sort -u`)

	kill -9 "${pids[@]}"

	sync
	for _ in {1..5}; do
		for mntpt in `mount | grep "$install_root"| awk '{print $3}' | sort -r`; 
		do 
			umount -R $mntpt
		done
	done

	[ -n "$msg" ] && echo "$msg"

	return 0
}

err_exit() {
	msg=$1

	sync && echo "$msg"
	
	exit 1
}

check_stratis_pool() {
	stratis pool list | grep -q $1
}

check_stratis_fs() {
	stratis filesystem list | grep -q $1
}

create_stratis_fs() {
	disk=$1
	key=$2
	pool=$3
	fs=$4

	
	check_stratis_pool $pool || stratis pool create --no-overprovision --key-desc $keyname $pool $disk
	sz=$(stratis pool | grep "$pool" | awk '{print int($8)$9}')
	stratis filesystem create --size $sz $pool $fs
}

devicepart_fmt() {
	if [[ "${device}" =~ "/dev/nvme" ]]; then
		echo "${device}p"
	else
		echo "${device}"
	fi
}

mk_required_dirs() {
	mkdir -p $install_root/{boot/efi,home,etc/default,proc,sys,dev,run,tmp,usr/local/bin}
}

format_disk() {

	fdisk $device <<PARTS
g
n


+1G
t
linux
n


+256M
t

uefi
n


+8G
t

swap
n



t

linux
w
PARTS

	devicefmt=$(devicepart_fmt)

	mkfs.ext4 "$devicefmt"1
	mkfs.vfat -F 32 "$devicefmt"2
	mkswap "$devicefmt"3
	swapon -a
	
	read -p "Keyname: " keyname

	stratis key set --capture-key $keyname
	check_stratis_fs "root" || create_stratis_fs "$devicefmt"4 $keyname root rfs 
	
	mount /dev/stratis/root/rfs "$install_root"
	mount "$devicefmt"1 $install_root/boot
	mount "$devicefmt"2 $install_root/boot/efi
	
	boot=`blkid -p --output export "$devicefmt"1 | grep -E '^UUID'`
	efi=`blkid -p --output export "$devicefmt"2 | grep -E '^UUID'`
	rid=`stratis pool list --name root | grep UUID | cut -d' ' -f 2`
	cryptroot=`blkid -p --output export "$devicefmt"4 | grep -E '^UUID'`
	
	printf "# Automagically generated
/dev/stratis/root/rfs\t/\txfs\tdefaults,x-systemd.requires=stratis-fstab-setup@$rid.service,x-systemd.after=stratis-fstab-setup@$rid.service 0 1
$boot\t/boot\t\text4\tdefaults 1 2
$efi\t/boot/efi\t\tvfat\tdefaults 0 2
# Encrypted swap
/dev/mapper/swap_crypt\t\t\tnone\t\tswap\tdefaults 0 0\n" > $install_root/etc/fstab

	partid=$(lsblk -o name,model,serial $device | awk 'NR==2{print $2"_"$3}')

	if [[ "${device}" =~ "/dev/nvme" ]]; then
		printf "# Crypttab
swap_crypt /dev/disk/by-id/nvme-$partid-part3 /dev/urandom swap,cipher=aes-cbc-essiv:sha256,size=256\n" > $install_root/etc/crypttab
	
	elif [[ "${device}" =~ "/dev/sd" ]]; then
		printf "# Crypttab
swap_crypt /dev/disk/by-id/ata-$partid-part3 /dev/urandom swap,cipher=aes-cbc-essiv:sha256,size=256\n" > $install_root/etc/crypttab


	fi
	chmod 600 $install_root/etc/crypttab



	echo "GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=\"$(sed 's, release .*$,,g' /etc/system-release)\"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT=\"console\"
GRUB_CMDLINE_LINUX=\"cryptdevice=$cryptroot root=/dev/stratis/root/rfs stratis.rootfs.pool_uuid=$rid\"
GRUB_DISABLE_RECOVERY=\"true\"
GRUB_ENABLE_BLSCFG=true
GRUB_ENABLE_CRYPTODISK=y" > $install_root/etc/default/grub

}

# Install stratis for live environment
dnf install stratisd stratisd-dracut stratis-cli -y
systemctl start stratisd

wipefs -a $device

mk_required_dirs
format_disk

mount --types proc /proc $install_root/proc
mount --rbind /sys $install_root/sys
mount --make-rslave $install_root/sys
mount --rbind /dev $install_root/dev
mount --make-rslave $install_root/dev
mount --bind /run $install_root/run
mount --make-slave $install_root/run
mount -t tmpfs /tmp $install_root/tmp  -o mode=1777,strictatime,nodev,nosuid


dnf install --installroot $install_root --releasever $rv -y @custom-environment which cryptsetup coreutils kernel efi-filesystem efibootmgr efitools efivar fwupd-efi grub2-efi-x64 grub2-efi-modules shim-x64 grub2-tools glibc-locale-source bash qemu-user-static rng-tools tar stratisd stratisd-dracut stratis-cli

[ $? -ge 3 ] && err_exit "Problem bootstraping minimal environment"

cp setup-env.sh $install_root/usr/local/bin/

if [ -n "$bkup" ]; then
	sha256sum -c "$bkup"\.shasum || err_exit "shasum mistach"
	tar xzvf "$bkup" -C "$install_root/home/" || err_exit "Error unpacking home"
fi

chroot "$install_root" /usr/local/bin/setup-env.sh || err_exit "Problem chrooting"

cleanup "Done.."
echo "Reboot into OS when you're ready"
