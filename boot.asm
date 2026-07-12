org 0x7C00
use16

start:
    mov [boot_drive], dl
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    in al, 0x92
    or al, 2
    out 0x92, al

    mov si, DAP
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jnc kernel_jump

    mov si, err_msg
    call print_str
    cli
    hlt

kernel_jump:
    xor ax, ax
    mov ds, ax
    mov es, ax
    jmp 0x1000:0x0000

print_str:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_str
.done:
    ret

boot_drive db 0
err_msg db "Aevum: Boot error", 0

DAP:
    db 0x10
    db 0
    dw 16
    dw 0x0000
    dw 0x1000
    dq 1

times 510-($-$$) db 0
dw 0xAA55
