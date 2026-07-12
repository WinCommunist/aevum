@echo off
chcp 65001 >nul
echo ===== Building Aevum OS =====

C:\fasm\FASM.EXE boot.asm boot.bin
if %errorlevel% neq 0 (
    echo [!] Boot build failed!
    exit /b 1
)
echo [ok] Boot sector: 512 bytes

C:\fasm\FASM.EXE kernel.asm kernel.bin
if %errorlevel% neq 0 (
    echo [!] Kernel build failed!
    exit /b 1
)
for %%I in (kernel.bin) do echo [ok] Kernel: %%~zI bytes

copy /b boot.bin + kernel.bin aevum.img >nul
echo [ok] Image: aevum.img
echo.
echo Ready to run: qemu-system-x86_64 -drive file=aevum.img,format=raw -m 64
