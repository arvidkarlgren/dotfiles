#!/bin/bash

# Installation device path (eg. /dev/nvme0n1)
device='/dev/sda'

# Hostname
hostname='arch-install'

# Present hardware (intel, amd, nvidia)
cpu='amd'
gpu='nvidia'

# User info
user="arvid"

setup() {
    echo -n "Password: "
    read -s password

#	if check_variables; then
#        echo "Running installer..."
#	    partition_device
#	
#	    partition_esp="$(ls ${device}* | grep 1)"
#	    partition_swap="$(ls ${device}* | grep 2)"
#	    partition_root="$(ls ${device}* | grep 3)"
#	
#	    format_partitions
#	    mount_filesystems
#	    install_base
#	    generate_fstab
#	
#	    cp $0 /mnt/setup.sh
#	    arch-chroot /mnt /setup.sh chroot

#        ./arch-install.sh chroot
#    fi
}

configure() {
#    echo "Running configure..."
#    set_timezone
#    set_locale
#    set_keymap
#    configure_network
#    install_grub
#    generate_initramfs
    configure_users
    
#    rm /setup.sh
}

check_variables() {
    if [ -z "${device}" ]; then
        echo "Device can not be empty!"
        return 1
    elif [ -z "${hostname}" ]; then
        echo "Hostname can not be empty!"
        return 1
    elif [ -z "${cpu}" ]; then
        echo "CPU can not be empty!"
        return 1
    elif [ -z "${gpu}" ]; then
        echo "GPU can not be empty!"
        return 1
    elif [ -z "${user}" ]; then
        echo "User can not be empty!"
        return 1
    elif [ -z "${password}" ]; then
        echo "Password can not be empty!"
        return 1
    else
        echo
        echo "-------------------------------------------"
        echo "The following install options will be used:"
        echo "Device: ${device}"
        echo "Hostname: ${hostname}"
        echo "CPU: ${cpu}"
        echo "GPU: ${gpu}"
        echo "User: ${user}"
        echo "-------------------------------------------"
        echo
        echo "Are these options correct? [y/N]"
        read response
        if [ "$response" == "y" ]; then
            return 0
        else
            return 1
        fi
    fi
}

partition_device() {
    parted --script "${device}" \
        mklabel gpt \
        mkpart '"EFI system partition"' fat32 1MiB 501MiB \
        mkpart '"Linux swap"' linux-swap 501MiB 8693MiB \
        mkpart '"Linux filesystem"' btrfs 8693MiB 100%
}

format_partitions() {
    echo "Formatting ${partition_esp} as FAT32" 
    dd if=/dev/zero of=${partition_esp} bs=512 count=1024
    mkfs.fat -F32 "${partition_esp}"
    echo
    echo "Formatting ${partition_swap} as Swap" 
    dd if=/dev/zero of=${partition_swap} bs=512 count=1024
    mkswap "${partition_swap}"
    echo
    echo "Formatting ${partition_root} as BTRFS" 
    dd if=/dev/zero of=${partition_root} bs=512 count=1024
    mkfs.btrfs ${partition_root}
    echo
}

mount_filesystems() {
    # Temporarily mount BTRFS root and create subvolumes
    mount "${partition_root}" /mnt
    btrfs subvolume create /mnt/@

    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    # Mount filesystems
    mount -o noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=@ "${partition_root}" /mnt
    
    mkdir /mnt/{home,.snapshots,efi}
    
    mount -o noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=@home "${partition_root}" /mnt/home
    mount -o noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=@snapshots "${partition_root}" /mnt/.snapshots

    mount "${partition_esp}" /mnt/efi

    swapon "${partition_swap}"
}

install_base() {
    # Base system
    local packages="base linux linux-firmware base-devel btrfs-progs grub grub-btrfs efibootmgr dosfstools os-prober mtools sudo networkmanager openssh git neovim"

    if [ "${cpu}" == "intel" ]; then
        packages+=" intel-ucode"
    elif [ "${cpu}" == "amd" ]; then
        packages+=" amd-ucode"
    else
        echo "Warning: No CPU ucode is being installed!"
    fi

    if ["${gpu}" == "nvidia" ]; then
        packages+=" nvidia nvidia-settings"
    else
        packages+=" mesa"
    fi
    
    # Install packages
    pacstrap -K /mnt ${packages}
}

generate_fstab() {
    cat >> /mnt/etc/fstab <<EOF
# Root
UUID=$(blkid -s UUID -o value ${partition_root})    /   btrfs   rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=/@   0   0

# Home
UUID=$(blkid -s UUID -o value ${partition_root})    /home   btrfs   rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=/@home   0   0

# Snapshots
UUID=$(blkid -s UUID -o value ${partition_root})    /.snapshots btrfs   rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=/@snapshots  0   0

# ESP
UUID=$(blkid -s UUID -o value ${partition_esp}) /efi    vfat    rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro   0   2

# Swap
UUID=$(blkid -s UUID -o value ${partition_swap})    none    swap    defaults    0   0
EOF
}

set_timezone() {

    ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
    hwclock --systohc
}

set_locale() {
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    echo "sv_SE.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    
    echo "LANG=en_US.UTF-8" >> /etc/locale.conf
    echo "LC_TIME=sv_SE.UTF-8" >> /etc/locale.conf
}

set_keymap(){
    echo "KEYMAP=sv-latin1" >> /etc/vconsole.conf
}

configure_network(){
    echo "${hostname}" >> /etc/hostname
    cat >> /etc/hosts <<EOF
${hostname}
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${hostname}.localdomain ${hostname}
EOF

    systemctl enable NetworkManager sshd
}

install_grub() {
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=grub
    grub-mkconfig -o /boot/grub/grub.cfg
}

generate_initramfs() {
    sed -i '/^MODULES=(/c\MODULES=(btrfs)' /etc/mkinitcpio.conf
    sed -i '/^HOOKS=(/c\HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck grub-btrfs-overlayfs)' /etc/mkinitcpio.conf

    mkinitcpio -p linux
}

configure_users() {
    echo "Password: ${password}"
#    # Set root password
#    echo -en "${password}\n${password}" | passwd
#
#    # Configure user
#    useradd -m "${user}"
#    echo -en "${password}\n${password}" | passwd arvid
#    usermod -aG wheel "${user}"
#    sed -i '/^# %wheel ALL=(ALL:ALL) ALL/c\%wheel ALL=(ALL:ALL) ALL' /etc/sudoers
}


if [ "$1" == "chroot" ]; then
    configure
else
    setup
    echo $password
fi
