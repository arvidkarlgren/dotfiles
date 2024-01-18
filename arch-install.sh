#!/bin/bash

device='/dev/sda'
hostname='arch-install'

setup() {
    partition_device

    partition_esp="$(ls ${device}* | grep 1)"
    partition_swap="$(ls ${device}* | grep 2)"
    partition_root="$(ls ${device}* | grep 3)"

    format_partitions

    mount_filesystems
}

message() {
    echo "${1}"
    echo
}

partition_device() {
    message "Partitioning device..."

    parted --script "${device}" \
        mklabel gpt \
        mkpart '"EFI system partition"' fat32 1MiB 501MiB \
        mkpart '"Linux swap"' linux-swap 501MiB 8693MiB \
        mkpart '"Linux filesystem"' btrfs 8693MiB 100%
}

format_partitions() {
    message "Formatting partitions..."

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
    message "Mounting filesystems..."

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

install_base_system() {
    #pacstrap -K /mnt base linux linux-firmware base-devel btrfs-progs git neovim grub grub-btrfs efibootmgr dosfstools os-prober mtools networkmanager openssh sudo

    echo "UUID=$(blkid -s UUID -o value ${partition_root}) \t / \t btrfs \t rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=/@ \t 0 \t 0"
}

setup
