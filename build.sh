#!/bin/sh
echo "===== Building Aevum OS ====="

fasm boot.asm boot.bin
if [ $? -ne 0 ]; then
    echo "[!] Boot build failed!"
    exit 1
fi
echo "[ok] Boot sector: $(wc -c < boot.bin) bytes"

fasm kernel.asm kernel.bin
if [ $? -ne 0 ]; then
    echo "[!] Kernel build failed!"
    exit 1
fi
echo "[ok] Kernel: $(wc -c < kernel.bin) bytes"

cat boot.bin kernel.bin > aevum.img
echo "[ok] Image: aevum.img"
echo ""
echo "Ready to run: qemu-system-x86_64 -drive file=aevum.img,format=raw -m 64"
