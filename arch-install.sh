#!/bin/bash

device='/dev/sda'
hostname='arch-install'

setup() {
    partition_device

    partition_esp="$(ls ${device}* | grep 1)"
    partition_swap="$(ls ${device}* | grep 2)"
    partition_root="$(ls ${device}* | grep 3)"

    format_partitions
}

message() {
    echo
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

    
    mkfs.fat -F32 "${partition_esp}"
    echo
    mkswap "${partition_swap}"
    echo
    mkfs.btrfs "${partition_root}"
    echo
}

mount_filesystems() {
    message "Mounting filesystems..."

    swapon "${device}"
}

setup
