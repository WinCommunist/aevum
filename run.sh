#!/bin/sh
echo "===== Aevum OS ====="
qemu-system-x86_64 -drive file=aevum.img,format=raw -m 64 -vga std
