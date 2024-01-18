#!/bin/bash

device='/dev/sda'
hostname='arch-install'

setup() {
    partition_device
    format_filesystems
}

partition_device() {
    parted --script "${device}" \
        mklabel gpt \
        mkpart '"EFI system partition"' fat32 1MiB 501MiB \
        mkpart '"Linux swap"' linux-swap 501MiB 8693MiB \
        mkpart '"Linux filesystem"' btrfs 8693MiB 100%
}

format_filesystems() {
    local partition_esp="$(ls ${device} | grep 1)"
    local partition_swap="$(ls ${device} | grep 2)"
    local partition_root="$(ls ${device} | grep 3)"
    echo "ESP: ${partition_esp}"
    echo "Swap: ${partition_swap}"
    echo "Root: ${partition_root}"
}

setup
