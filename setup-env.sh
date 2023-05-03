set -e

localedef --inputfile=en_US --charmap=UTF-8 en_US.UTF-8

grub2-mkconfig -o /etc/grub2.cfg
grub2-mkconfig -o /etc/grub2-efi.cfg
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf

read -p "Username: " user
groupadd -g 1000 $user
useradd -u 1000 -g 1000 $user -G wheel
userhome=/home/$user
mkdir -p $userhome
chown -R $user:$user $userhome
passwd $user

systemctl enable stratisd

dnf reinstall polkit selinux-policy -y

kernel_ver=$(ls /boot/config-* | cut -d '-' -f2-)
rescue_kernel=$(ls -tr /boot/*-0-rescue-* | cut -d '-' -f2- | tail -1)
dracut --add stratis stratis-clevis --force --strip --kver $kernel_ver
dracut --add stratis stratis-clevis --force --strip --kver $kernel_ver $(ls /boot/initramfs-0-rescue-*)
echo "initramfs images updated for $kernel_ver"

usermod -L root
