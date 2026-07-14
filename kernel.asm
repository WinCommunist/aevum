; Aevum OS - Kernel
; Capability-Based Fractal Kernel
; Not Unix, not DOS
; Flat Assembler (FASM)

org 0
use16

K = 0x10000
VM = 0xB8000
SW = 80
SH = 25
BS = 0x08
LF = 0x0A
CR = 0x0D

; ===== Real Mode Entry =====
start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x1000

    in al, 0x92
    or al, 2
    out 0x92, al

    xor eax, eax
    mov ax, cs
    shl eax, 4
    add eax, gdt
    mov [gdt_desc+2], eax
    lgdt [gdt_desc]

    mov eax, cr0
    or al, 1
    mov cr0, eax

    db 0x66
    db 0xEA
    dd pm_entry + K
    dw 0x08

; ===== GDT =====
align 4
gdt:
    dq 0
    db 0xFF, 0xFF, 0, 0, 0, 0x9A, 0xCF, 0
    db 0xFF, 0xFF, 0, 0, 0, 0x92, 0xCF, 0
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd 0

; ===== Protected Mode Entry =====
use32
pm_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x20000

    call serial_init
    call clr_scr
    call splash

    call shell

; ===== Serial Debug =====
SPORT = 0x3F8
serial_init:
    push eax edx
    mov dx, SPORT + 3
    mov al, 0x80
    out dx, al
    mov dx, SPORT
    mov al, 1
    out dx, al
    mov dx, SPORT + 1
    xor al, al
    out dx, al
    mov dx, SPORT + 3
    mov al, 3
    out dx, al
    mov dx, SPORT + 4
    mov al, 3
    out dx, al
    pop edx eax
    ret

serial_putc:
    push edx eax
    mov dx, SPORT + 5
.l:
    in al, dx
    test al, 0x20
    jz .l
    mov dx, SPORT
    pop eax
    out dx, al
    pop edx
    ret

; ===== VGA Text Mode =====
clr_scr:
    push eax ecx edi
    mov edi, VM
    movzx eax, byte [color_attr+K]
    mov ah, al
    mov al, 0x20
    mov ecx, SW*SH
    rep stosw
    mov [cursor_row+K], byte 0
    mov [cursor_col+K], byte 0
    call upd_cur
    pop edi ecx eax
    ret

upd_cur:
    push eax ebx edx
    movzx eax, byte [cursor_row+K]
    mov ebx, SW
    mul ebx
    movzx ebx, byte [cursor_col+K]
    add eax, ebx
    mov ebx, eax
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    dec dx
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    pop edx ebx eax
    ret

scroll:
    push eax ecx esi edi
    mov esi, VM + SW*2
    mov edi, VM
    mov ecx, (SH-1)*SW
    cld
    rep movsw
    mov edi, VM + (SH-1)*SW*2
    movzx eax, byte [color_attr+K]
    mov ah, al
    mov al, 0x20
    mov ecx, SW
    rep stosw
    mov [cursor_row+K], byte SH-1
    mov [cursor_col+K], byte 0
    pop edi esi ecx eax
    ret

nl:
    push eax
    mov [cursor_col+K], byte 0
    inc byte [cursor_row+K]
    cmp byte [cursor_row+K], SH
    jb .ok
    call scroll
.ok:
    call upd_cur
    pop eax
    ret

putc:
    push eax ebx ecx edx edi
    push eax
    call serial_putc
    pop eax
    mov ecx, eax
    movzx eax, byte [cursor_row+K]
    mov ebx, SW
    mul ebx
    movzx ebx, byte [cursor_col+K]
    add eax, ebx

    cmp cl, LF
    je .nl
    cmp cl, CR
    je .cr
    cmp cl, BS
    je .bs

    shl eax, 1
    add eax, VM
    mov [eax], cl
    push ecx
    mov cl, [color_attr+K]
    mov [eax+1], cl
    pop ecx
    inc byte [cursor_col+K]
    cmp byte [cursor_col+K], SW
    jb .done

.nl:
    mov [cursor_col+K], byte 0
    inc byte [cursor_row+K]
    cmp byte [cursor_row+K], SH
    jb .done
    call scroll
    jmp .done

.cr:
    mov [cursor_col+K], byte 0
    jmp .done

.bs:
    cmp byte [cursor_col+K], 0
    jz .done
    dec byte [cursor_col+K]
    movzx eax, byte [cursor_row+K]
    mov ebx, SW
    mul ebx
    movzx ebx, byte [cursor_col+K]
    add eax, ebx
    shl eax, 1
    add eax, VM
    mov word [eax], 0x0720

.done:
    call upd_cur
    pop edi edx ecx ebx eax
    ret

puts:
    push eax esi
.l:
    lodsb
    or al, al
    jz .d
    call putc
    jmp .l
.d:
    pop esi eax
    ret

; ===== Keyboard (polling) =====
wait_key:
    push edx ebx
.l:
    in al, 0x64
    test al, 1
    jz .l
    in al, 0x60
    movzx ebx, al
    and ebx, 0x7F
    test al, 0x80
    jnz .rel
    cmp bl, 0x2A
    je .son
    cmp bl, 0x36
    je .son
    cmp bl, 0x1C
    je .ent
    cmp bl, 0x0E
    je .bsp
    cmp bl, 0x39
    je .spc
    cmp bl, 0x0F
    je .tab
    cmp bl, 0x01
    je .esc
    cmp bl, 0x3A
    jae .l
    test [shift_f+K], 1
    jnz .shf
    mov al, [sc_norm+ebx+K]
    jmp .done
.shf:
    mov al, [sc_shft+ebx+K]
    jmp .done
.son:
    mov [shift_f+K], byte 1
    jmp .l
.rel:
    cmp bl, 0x2A
    je .soff
    cmp bl, 0x36
    je .soff
    jmp .l
.soff:
    mov [shift_f+K], byte 0
    jmp .l
.ent:
    mov al, LF
    jmp .done
.bsp:
    mov al, BS
    jmp .done
.spc:
    mov al, ' '
    jmp .done
.tab:
    mov al, ' '
    jmp .done
.esc:
    xor al, al
.done:
    pop ebx edx
    ret

; ===== String Helpers =====
skip_spc:
.l:
    cmp byte [esi], ' '
    jne .d
    inc esi
    jmp .l
.d:
    ret

skip_tok:
.l:
    lodsb
    cmp al, ' '
    je .d
    or al, al
    jnz .l
    dec esi
.d:
    ret

strcmp:
    push esi edi ecx
.l:
    lodsb
    cmp al, ' '
    je .check_end
    mov cl, [edi]
    cmp al, cl
    jne .diff
    or al, al
    jz .same
    inc edi
    jmp .l
.check_end:
    cmp byte [edi], 0
    je .same
.diff:
    mov al, 1
    jmp .end
.same:
    xor eax, eax
.end:
    pop ecx edi esi
    ret

atoi:
    push ebx
    xor eax, eax
.l:
    movzx ebx, byte [esi]
    cmp bl, '0'
    jb .d
    cmp bl, '9'
    ja .d
    sub bl, '0'
    imul eax, 10
    add eax, ebx
    inc esi
    jmp .l
.d:
    pop ebx
    ret

itoa:
    push eax ebx edx ecx
    mov edi, num_buf+K+15
    mov byte [edi], 0
    dec edi
    mov ebx, 10
    xor ecx, ecx
    test eax, eax
    jnz .chk_sign
    mov byte [edi], '0'
    dec edi
    jmp .d
.chk_sign:
    jns .l
    inc ecx
    neg eax
.l:
    xor edx, edx
    div ebx
    add dl, '0'
    mov [edi], dl
    dec edi
    or eax, eax
    jnz .l
    test ecx, ecx
    jz .d
    mov byte [edi], '-'
    dec edi
.d:
    inc edi
    mov esi, edi
    pop ecx edx ebx eax
    ret

; ===== Shell =====
shell:
.l:
    mov al, [color_attr+K]
    push eax
    and al, 0xF0
    or al, 0x0A
    call set_color
    mov esi, msg_prompt+K
    call puts
    pop eax
    call set_color
    mov [cmd_len+K], byte 0
.read:
    call wait_key
    or al, al
    jz .read
    cmp al, LF
    je .exec
    cmp al, BS
    je .bksp
    movzx edi, byte [cmd_len+K]
    cmp edi, 254
    jae .read
    mov [cmd_buf+edi+K], al
    inc byte [cmd_len+K]
    call putc
    jmp .read
.bksp:
    movzx edi, byte [cmd_len+K]
    or edi, edi
    jz .read
    dec byte [cmd_len+K]
    call putc
    jmp .read
.exec:
    call nl
    movzx edi, byte [cmd_len+K]
    mov [cmd_buf+edi+K], byte 0
    cmp edi, 0
    je .l
    call exec_cmd
    jmp .l

exec_cmd:
    push esi edi
    mov esi, cmd_buf+K
    call skip_spc
    or al, al
    jz .end

    mov edi, tok_help+K
    call strcmp
    jnz .n1
    call cmd_help
    jmp .end
.n1:
    mov edi, tok_info+K
    call strcmp
    jnz .n2
    call cmd_info
    jmp .end
.n2:
    mov edi, tok_caps+K
    call strcmp
    jnz .n3
    call cmd_caps
    jmp .end
.n3:
    mov edi, tok_invoke+K
    call strcmp
    jnz .n4
    call cmd_invoke
    jmp .end
.n4:
    mov edi, tok_tasks+K
    call strcmp
    jnz .n5
    call cmd_tasks
    jmp .end
.n5:
    mov edi, tok_echo+K
    call strcmp
    jnz .n6
    call cmd_echo
    jmp .end
.n6:
    mov edi, tok_calc+K
    call strcmp
    jnz .n7
    call cmd_calc
    jmp .end
.n7:
    mov edi, tok_clear+K
    call strcmp
    jnz .n8
    call clr_scr
    jmp .end
.n8:
    mov edi, tok_ver+K
    call strcmp
    jnz .n9
    call cmd_ver
    jmp .end
.n9:
    mov edi, tok_who+K
    call strcmp
    jnz .n10
    call cmd_who
    jmp .end
.n10:
    mov edi, tok_color+K
    call strcmp
    jnz .n11
    call cmd_color
    jmp .end
.n11:
    mov edi, tok_halt+K
    call strcmp
    jnz .n12
    call cmd_halt
    jmp .end
.n12:
    mov al, [color_attr+K]
    push eax
    mov al, 0x0C
    call set_color
    mov esi, msg_unknown+K
    call puts
    pop eax
    call set_color
.end:
    call nl
    pop edi esi
    ret

; ===== Command Handlers =====
cmd_color:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .usage
    dec esi
    call atoi
    cmp eax, 15
    ja .usage
    movzx ecx, al
    call skip_spc
    lodsb
    or al, al
    jz .set_fg
    dec esi
    push ecx
    call atoi
    cmp eax, 7
    ja .usage_pop
    shl eax, 4
    pop ecx
    or eax, ecx
    mov [color_attr+K], al
    ret
.set_fg:
    mov [color_attr+K], cl
    ret
.usage_pop:
    pop ecx
.usage:
    mov esi, msg_color_usage+K
    call puts
    ret

cmd_help:
    mov esi, msg_help+K
    call puts
    ret

cmd_info:
    mov esi, msg_info+K
    call puts
    ret

cmd_caps:
    mov esi, msg_caps_hdr+K
    call puts
    mov edi, cap_list+K
.l:
    mov esi, [edi]
    or esi, esi
    jz .d
    push edi
    call puts
    pop edi
    call nl
    add edi, 8
    jmp .l
.d:
    ret

cmd_invoke:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    movzx edx, byte [esi]
    or edx, edx
    jz .usage

    mov edi, cap_list+K
.l:
    mov ecx, [edi]
    or ecx, ecx
    jz .nf
    push esi edi
    mov edi, ecx
    call strcmp
    pop edi esi
    or eax, eax
    jz .found
    add edi, 8
    jmp .l

.found:
    mov ecx, [edi+4]
    or ecx, ecx
    jz .no_handler
    call ecx
    ret
.no_handler:
    mov esi, msg_inv_ok+K
    call puts
    ret
.nf:
    mov esi, msg_no_cap+K
    call puts
    ret
.usage:
    mov esi, msg_inv_usage+K
    call puts
    ret

cmd_tasks:
    mov esi, msg_tasks_hdr+K
    call puts
    mov edi, task_list+K
.l:
    mov eax, [edi]
    or eax, eax
    jz .d
    mov esi, edi
    call puts
    call nl
    add edi, 16
    jmp .l
.d:
    ret

cmd_echo:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .d
    dec esi
    call puts
.d:
    ret

cmd_calc:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .usage
    dec esi
    call atoi
    push eax
    call skip_spc
    lodsb
    mov bl, al
    call skip_spc
    lodsb
    or al, al
    jz .usage
    dec esi
    call atoi
    mov ecx, eax
    pop eax
    cmp bl, '+'
    je .add
    cmp bl, '-'
    je .sub
    cmp bl, '*'
    je .mul
    cmp bl, '/'
    je .div
    mov esi, msg_bad_op+K
    call puts
    ret
.add:
    add eax, ecx
    jmp .show
.sub:
    sub eax, ecx
    jmp .show
.mul:
    mul ecx
    jmp .show
.div:
    or ecx, ecx
    jz .div0
    xor edx, edx
    div ecx
    jmp .show
.div0:
    mov esi, msg_div0+K
    call puts
    ret
.show:
    call itoa
    call puts
    ret
.usage:
    mov esi, msg_calc_usage+K
    call puts
    ret

cmd_ver:
    mov esi, msg_ver+K
    call puts
    ret

cmd_who:
    mov esi, msg_who+K
    call puts
    ret

cmd_halt:
    mov al, [color_attr+K]
    push eax
    mov al, 0x0C
    call set_color
    mov esi, msg_halt+K
    call puts
    pop eax
    call set_color
    cli
.l:
    hlt
    jmp .l

; ===== Archive Capability Handlers =====
arc_list_handler:
    mov edi, [archive_ptr+K]
    or edi, edi
    jz .bad
    cmp [edi], dword 'AARC'
    jne .bad
    mov ecx, [edi+8]
    add edi, 16
    mov esi, msg_arc_hdr+K
    call puts
.l:
    or ecx, ecx
    jz .d
    push ecx
    mov esi, edi
    call puts
    call nl
    pop ecx
    add edi, 32
    dec ecx
    jmp .l
.d:
    ret
.bad:
    mov esi, msg_arc_bad+K
    call puts
    ret

arc_read_handler:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .usage
    dec esi
    call arc_find_entry
    or eax, eax
    jz .nf
    mov esi, eax
    call puts
    ret
.nf:
    mov esi, msg_arc_nf+K
    call puts
    ret
.usage:
    mov esi, msg_arc_read_usage+K
    call puts
    ret

arc_info_handler:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .usage
    dec esi
    call arc_find_entry
    or eax, eax
    jz .nf
    mov esi, msg_arc_info_hdr+K
    call puts
    mov esi, msg_arc_size+K
    call puts
    mov eax, edx
    call itoa
    call puts
    call nl
    ret
.nf:
    mov esi, msg_arc_nf+K
    call puts
    ret
.usage:
    mov esi, msg_arc_info_usage+K
    call puts
    ret

; ===== ATA Driver =====
ata_identify:
    push edx ecx edi
    mov edi, ata_buf+K
    mov ecx, eax
    mov dx, 0x1F0
    test al, 2
    jz .sel
    mov dx, 0x170
.sel:
    push dx
    add dx, 6
    mov al, 0xA0
    test cl, 1
    jz .drv
    or al, 0x10
.drv:
    out dx, al
    inc dx
    mov ecx, 10000
.busy:
    in al, dx
    test al, 0x80
    jz .ready
    dec ecx
    jnz .busy
    jmp .no
.ready:
    cmp al, 0xFF
    je .no
    mov al, 0xEC
    out dx, al
    mov ecx, 10000
.poll:
    in al, dx
    test al, 0x80
    jnz .poll
    test al, 1
    jnz .no
    test al, 0x08
    jz .no
    pop dx
    mov ecx, 256
    rep insw
    mov eax, 1
    pop edi ecx edx
    ret
.no:
    pop dx
    xor eax, eax
    pop edi ecx edx
    ret

ata_print_size:
    push eax edx ecx
    mov eax, dword [ata_buf+K + 120]
    cmp eax, 2097152
    jb .show_mb
    xor edx, edx
    mov ecx, 2097152
    div ecx
    call itoa
    call puts
    mov esi, msg_size_gb+K
    call puts
    pop ecx edx eax
    ret
.show_mb:
    xor edx, edx
    mov ecx, 2048
    div ecx
    call itoa
    call puts
    mov esi, msg_size_mb+K
    call puts
    pop ecx edx eax
    ret

ata_copy_model:
    push edi ecx
    mov esi, ata_buf+K + 54
    mov edi, ata_model+K
    mov ecx, 20
.l:
    lodsw
    xchg al, ah
    stosw
    dec ecx
    jnz .l
    mov byte [edi], 0
    pop ecx edi
    ret

; ===== ATA PIO Read/Write =====
; eax = drive (0-3), ebx = LBA, reads one sector into ata_buf, returns eax = 1/0
ata_read_sector:
    push ecx edx edi
    mov ecx, eax
    mov edi, ebx
    mov dx, 0x1F0
    test cl, 2
    jz .rsel
    mov dx, 0x170
.rsel:
    push dx
    add dl, 2
    mov al, 1
    out dx, al
    inc dx
    mov eax, edi
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    and al, 0x0F
    or al, 0xE0
    test cl, 1
    jz .rdrv
    or al, 0x10
.rdrv:
    out dx, al
    inc dx
    mov cx, 0xFFFF
.rwait:
    in al, 0x80
    in al, dx
    test al, 0x80
    jz .rgo
    dec cx
    jnz .rwait
    jmp .rfail
.rgo:
    mov al, 0x20
    out dx, al
    mov cx, 0xFFFF
.rpoll:
    in al, dx
    test al, 0x80
    jz .rrdy
    dec cx
    jnz .rpoll
    jmp .rfail
.rrdy:
    test al, 1
    jnz .rfail
    test al, 0x08
    jz .rfail
    pop dx
    mov edi, ata_buf+K
    mov cx, 256
.rw2:
    in ax, dx
    stosw
    dec cx
    jnz .rw2
    mov eax, 1
    pop edi edx ecx
    ret
.rfail:
    pop dx
    xor eax, eax
    pop edi edx ecx
    ret

; eax = drive (0-3), ebx = LBA, esi = data buffer (512 bytes), returns eax = 1/0
ata_write_sector:
    push ecx edx
    mov ecx, eax
    mov dx, 0x1F0
    test cl, 2
    jz .wsel
    mov dx, 0x170
.wsel:
    push dx
    add dl, 2
    mov al, 1
    out dx, al
    inc dx
    mov eax, ebx
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    out dx, al
    inc dx
    shr eax, 8
    and al, 0x0F
    or al, 0xE0
    test cl, 1
    jz .wdrv
    or al, 0x10
.wdrv:
    out dx, al
    inc dx
    mov cx, 0xFFFF
.wwait:
    in al, 0x80
    in al, dx
    test al, 0x80
    jz .wgo
    dec cx
    jnz .wwait
    jmp .wfail
.wgo:
    mov al, 0x30
    out dx, al
    mov cx, 0xFFFF
.wpoll:
    in al, dx
    test al, 0x80
    jz .wrdy
    dec cx
    jnz .wpoll
    jmp .wfail
.wrdy:
    test al, 1
    jnz .wfail
    test al, 0x08
    jz .wfail
    pop dx
    mov cx, 256
.ww2:
    lodsw
    out dx, ax
    dec cx
    jnz .ww2
    push dx
    add dl, 7
    mov cx, 0xFFFF
.wbusy:
    in al, dx
    test al, 0x80
    jz .wrdy2
    dec cx
    jnz .wbusy
    jmp .wfail
.wrdy2:
    test al, 1
    jnz .wfail
    pop dx
    mov eax, 1
    pop edx ecx
    ret
.wfail:
    pop dx
    xor eax, eax
    pop edx ecx
    ret

; ===== Disk Capability Handlers =====
disk_show_drive:
    push eax
    call ata_identify
    or eax, eax
    jz .no
    call ata_copy_model
    mov esi, ata_model+K
    call puts
    mov esi, msg_size_sep+K
    call puts
    call ata_print_size
    call nl
    pop eax
    ret
.no:
    mov esi, msg_disk_no+K
    call puts
    pop eax
    ret

disk_list_handler:
    mov esi, msg_disk_hdr+K
    call puts
    mov esi, msg_disk_pri_m+K
    call puts
    xor eax, eax
    call disk_show_drive
    mov esi, msg_disk_pri_s+K
    call puts
    mov eax, 1
    call disk_show_drive
    mov esi, msg_disk_sec_m+K
    call puts
    mov eax, 2
    call disk_show_drive
    mov esi, msg_disk_sec_s+K
    call puts
    mov eax, 3
    call disk_show_drive
    ret

disk_info_handler:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .all
    dec esi
    push esi
    mov edi, tok_disk_mst+K
    call strcmp
    or eax, eax
    jz .drive0
    pop esi
    push esi
    mov edi, tok_disk_slv+K
    call strcmp
    or eax, eax
    jz .drive1
    pop esi
    jmp .usage
.drive0:
    pop esi
    mov esi, msg_disk_pri_m+K
    call puts
    xor eax, eax
    call disk_show_drive
    ret
.drive1:
    pop esi
    mov esi, msg_disk_pri_s+K
    call puts
    mov eax, 1
    call disk_show_drive
    ret
.all:
    call disk_list_handler
    ret
.usage:
    mov esi, msg_disk_info_usage+K
    call puts
    ret

; ===== System Install =====
sys_install_handler:
    mov esi, cmd_buf+K
    call skip_tok
    call skip_spc
    call skip_tok
    call skip_spc
    lodsb
    or al, al
    jz .usage
    dec esi
    push esi
    mov edi, tok_disk_mst+K
    call strcmp
    or eax, eax
    jz .drive0
    pop esi
    push esi
    mov edi, tok_disk_slv+K
    call strcmp
    or eax, eax
    jz .drive1
    pop esi
    movzx eax, byte [esi]
    sub al, '0'
    cmp al, 3
    ja .usage
    jmp .do
.drive0:
    pop esi
    xor eax, eax
    jmp .do
.drive1:
    pop esi
    mov eax, 1
.do:
    push eax
    mov esi, msg_install_to+K
    call puts
    mov al, byte [esp]
    add al, '0'
    mov [num_buf+K], al
    mov byte [num_buf+K+1], 0
    mov esi, num_buf+K
    call puts
    mov esi, msg_colon+K
    call puts

    pop eax
    push eax
    xor ebx, ebx
    mov esi, 0x7C00
    mov edi, ata_buf+K
    mov ecx, 128
    rep movsd
    mov esi, ata_buf+K
    call ata_write_sector
    or eax, eax
    jnz .wr_ok
    pop eax
    mov esi, msg_install_fail+K
    call puts
    ret
.wr_ok:
    pop eax
    push eax
    mov ebx, 1
    mov ecx, 32
    mov edx, K
.kloop:
    mov esi, edx
    call ata_write_sector
    or eax, eax
    jnz .kr_ok
    pop eax
    mov esi, msg_install_fail+K
    call puts
    ret
.kr_ok:
    add edx, 512
    inc ebx
    dec ecx
    jnz .kloop
    pop eax
    mov esi, msg_install_done+K
    call puts
    ret
.usage:
    mov esi, msg_sys_install_usage+K
    call puts
    ret

; ===== System Info =====
sys_info_handler:
    push eax ebx ecx edx esi edi
    mov esi, msg_sysinfo_hdr+K
    call puts

    ; --- CPU ---
    mov esi, msg_info_cpu+K
    call puts
    pushfd
    pushfd
    xor dword [esp], 0x200000
    popfd
    pushfd
    pop eax
    xor eax, [esp]
    add esp, 4
    test eax, 0x200000
    jz .no_cpuid
    mov eax, 0
    cpuid
    mov dword [num_buf+K], ebx
    mov dword [num_buf+K+4], edx
    mov dword [num_buf+K+8], ecx
    mov byte [num_buf+K+12], 0
    mov esi, num_buf+K
    call puts
    mov eax, 1
    cpuid
    mov byte [num_buf+K], ' '
    mov byte [num_buf+K+1], '('
    mov byte [num_buf+K+2], 0
    mov esi, num_buf+K
    call puts
    mov eax, ebx
    shr eax, 16
    and eax, 0xFF
    call itoa
    call puts
    mov esi, msg_cpu_threads+K
    call puts
    call nl
    jmp .mem
.no_cpuid:
    mov esi, msg_na+K
    call puts
    call nl
.mem:
    ; --- Memory ---
    mov esi, msg_info_ram+K
    call puts
    xor eax, eax
    mov ax, [0x413]
    call itoa
    call puts
    mov esi, msg_kb+K
    call puts
    mov al, 0x30
    out 0x70, al
    in al, 0x71
    mov ah, al
    mov al, 0x31
    out 0x70, al
    in al, 0x71
    xchg al, ah
    or eax, eax
    jz .no_ext
    push eax
    mov esi, msg_sep_comma+K
    call puts
    pop eax
    call itoa
    call puts
    mov esi, msg_kb_ext+K
    call puts
    call nl
    jmp .disks
.no_ext:
    call nl
.disks:
    mov esi, msg_info_disk+K
    call puts
    mov esi, msg_disk_pri_m+K
    call puts
    xor eax, eax
    call disk_show_drive
    mov esi, msg_disk_pri_s+K
    call puts
    mov eax, 1
    call disk_show_drive
    mov esi, msg_disk_sec_m+K
    call puts
    mov eax, 2
    call disk_show_drive
    mov esi, msg_disk_sec_s+K
    call puts
    mov eax, 3
    call disk_show_drive
    pop edi esi edx ecx ebx eax
    ret

; ===== Splash =====
splash:
    mov al, 0x0B
    call set_color
    mov esi, msg_sep+K
    call puts
    mov al, 0x0F
    call set_color
    mov esi, msg_title+K
    call puts
    mov al, 0x02
    call set_color
    mov esi, msg_kernel+K
    call puts
    mov al, 0x0E
    call set_color
    mov esi, msg_not+K
    call puts
    mov al, 0x0B
    call set_color
    mov esi, msg_sep+K
    call puts
    mov al, 0x07
    call set_color
    mov esi, msg_help_txt+K
    call puts
    ret

set_color:
    mov [color_attr+K], al
    ret

serial_puts:
    push eax esi
.l:
    lodsb
    or al, al
    jz .d
    call serial_putc
    jmp .l
.d:
    pop esi eax
    ret

; ===== Archive Functions =====
arc_find_entry:
    push edi ecx
    mov edi, [archive_ptr+K]
    or edi, edi
    jz .nf
    cmp [edi], dword 'AARC'
    jne .nf
    mov ecx, [edi+8]
    add edi, 16
.l:
    or ecx, ecx
    jz .nf
    push esi edi ecx
    mov edi, edi
    call strcmp
    pop ecx edi esi
    or eax, eax
    jz .found
    add edi, 32
    dec ecx
    jmp .l
.found:
    mov eax, [edi+28]
    add eax, [archive_ptr+K]
    mov edx, [edi+24]
    pop ecx edi
    ret
.nf:
    xor eax, eax
    pop ecx edi
    ret

; ===== Data =====
align 4
cursor_row db 0
cursor_col db 0
shift_f db 0
color_attr db 0x07
cmd_len db 0
cmd_buf rb 256
num_buf rb 16
archive_ptr dd K + archive_start
ata_buf rb 512
ata_model rb 41

; --- Scancode Tables (US layout) ---
sc_norm:
db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=',0,0
db 'q','w','e','r','t','y','u','i','o','p','[',']',0,0,'a','s'
db 'd','f','g','h','j','k','l',';',0x27,'`',0,0x5C,'z','x','c','v'
db 'b','n','m',',','.','/',0,'*',0,' ',0,0,0,0,0,0
times 64 db 0

sc_shft:
db 0, 0, '!','@','#','$','%','^','&','*','(',')','_','+',0,0
db 'Q','W','E','R','T','Y','U','I','O','P','{','}',0,0,'A','S'
db 'D','F','G','H','J','K','L',':','"','~',0,'|','Z','X','C','V'
db 'B','N','M','<','>','?',0,'*',0,' ',0,0,0,0,0,0
times 64 db 0

; --- Capability Table ---
cap_list:
dd cap1_name+K, 0
dd cap2_name+K, 0
dd cap3_name+K, sys_info_handler+K
dd cap4_name+K, 0
dd cap5_name+K, arc_list_handler+K
dd cap6_name+K, arc_read_handler+K
dd cap7_name+K, arc_info_handler+K
dd cap8_name+K, disk_list_handler+K
dd cap9_name+K, disk_info_handler+K
dd cap10_name+K, sys_install_handler+K
dd 0

cap1_name db "console", 0
cap2_name db "mem.info", 0
cap3_name db "sys.info", 0
cap4_name db "task.list", 0
cap5_name db "arc.list", 0
cap6_name db "arc.read", 0
cap7_name db "arc.info", 0
cap8_name db "disk.list", 0
cap9_name db "disk.info", 0
cap10_name db "sys.install", 0

; --- Task Table ---
task_list:
db "root        ", 0, 0, 0, 0
db "  shell     ", 0, 0, 0, 0
db "    invoke  ", 0, 0, 0, 0
dd 0

; --- Strings ---
msg_sep db "========================================", LF, 0
msg_title db "       A E V U M   O S   v0.1.3.0", LF
db "            (Pre-Alpha)", LF, 0
msg_kernel db "   Capability-Based Fractal Kernel", LF, 0
msg_not db "      Not Unix  /  Not DOS", LF, 0
msg_help_txt db "     Type 'help' for commands", LF, 0

msg_info db "=== Aevum OS ===", LF
db "Version: 0.1.3.0 (Pre-Alpha)", LF
db "Kernel: Capability-Based Fractal", LF
db "IPC: Message-Oriented via Capabilities", LF
db "Process Model: Task Hierarchy", LF
db "Storage: Archive-Based", LF
db "Not Unix-compatible. Not DOS-compatible.", LF
db "Unique architecture.", LF, 0

msg_help db "Commands:", LF
db "  color     - set text color", LF
db "  help      - this help", LF
db "  info      - system info", LF
db "  caps      - list capabilities", LF
db "  invoke    - invoke capability", LF
db "  tasks     - show task hierarchy", LF
db "  echo      - print text", LF
db "  calc      - calculator", LF
db "  clear     - clear screen", LF
db "  version   - show version", LF
db "  whoami    - current user", LF
db "  halt      - halt system", LF, 0

msg_prompt db "aevum$ ", 0
msg_unknown db "Unknown command. Type help.", 0
msg_ver db "Aevum OS version 0.1.3.0", 0
msg_who db "guest@aevum (capability level: user)", 0
msg_caps_hdr db "Capabilities:", LF, 0
msg_no_cap db "Capability not found", 0
msg_inv_ok db "Capability invoked", 0
msg_inv_usage db "Usage: invoke <name>", 0
msg_tasks_hdr db "Task Hierarchy:", LF, 0
msg_calc_usage db "Usage: calc <a> <op> <b>", 0
msg_bad_op db "Bad operator. Use + - * /", 0
msg_div0 db "Division by zero", 0
msg_halt db "System halted.", 0
msg_color_usage db "Usage: color <fg> [bg]  (fg:0-15, bg:0-7)", 0

tok_color db "color", 0
tok_help db "help", 0
tok_info db "info", 0
tok_caps db "caps", 0
tok_invoke db "invoke", 0
tok_tasks db "tasks", 0
tok_echo db "echo", 0
tok_calc db "calc", 0
tok_clear db "clear", 0
tok_ver db "version", 0
tok_who db "whoami", 0
tok_halt db "halt", 0

; --- Archive Strings ---
msg_arc_hdr db "Archive entries:", LF, 0
msg_arc_nf db "Entry not found", 0
msg_arc_bad db "Archive corrupted", 0
msg_arc_read_usage db "Usage: invoke arc.read <name>", 0
msg_arc_info_hdr db "Entry info:", LF, 0
msg_arc_size db "Size: ", 0
msg_arc_info_usage db "Usage: invoke arc.info <name>", 0

; --- Disk Strings ---
msg_disk_hdr db "Disks:", LF, 0
msg_disk_pri_m db "  Primary Master: ", 0
msg_disk_pri_s db "  Primary Slave: ", 0
msg_disk_sec_m db "  Secondary Master: ", 0
msg_disk_sec_s db "  Secondary Slave: ", 0
msg_disk_no db "(not present)", LF, 0
msg_size_sep db " (", 0
msg_size_gb db " GB)", 0
msg_size_mb db " MB)", 0
msg_disk_info_usage db "Usage: invoke disk.info [master|slave]", 0
msg_sys_install_usage db "Usage: invoke sys.install [master|slave|0-3]", 0
msg_install_to db "Installing to drive ", 0
msg_colon db "...", LF, 0
msg_install_done db "Install complete!", LF, 0
msg_install_fail db "Install failed!", LF, 0
msg_sysinfo_hdr db LF, "=== System Info ===", LF, 0
msg_info_cpu db "CPU: ", 0
msg_info_ram db "RAM: ", 0
msg_info_disk db LF, "Disks:", LF, 0
msg_kb db " KB base", 0
msg_kb_ext db " KB extended", 0
msg_sep_comma db ", ", 0
msg_cpu_threads db " thread(s))", LF, 0
msg_na db "N/A", 0
tok_disk_mst db "master", 0
tok_disk_slv db "slave", 0

; --- Archive Data (AARC format) ---
archive_start:
  db "AARC"
  dd 1
  dd 4
  dd archive_entries_end - archive_start
archive_entries:
entry0_name db "about", 0
times 24 - ($ - entry0_name) db 0
dd entry0_end - entry0_data
dd entry0_data - archive_start

entry1_name db "philosophy", 0
times 24 - ($ - entry1_name) db 0
dd entry1_end - entry1_data
dd entry1_data - archive_start

entry2_name db "commands", 0
times 24 - ($ - entry2_name) db 0
dd entry2_end - entry2_data
dd entry2_data - archive_start

entry3_name db "license", 0
times 24 - ($ - entry3_name) db 0
dd entry3_end - entry3_data
dd entry3_data - archive_start

archive_entries_end:

entry0_data:
  db "Aevum OS v0.1.3.0", LF
  db "Capability-Based Fractal Kernel", LF
  db "Not Unix. Not DOS.", 0
entry0_end:

entry1_data:
  db "Aevum is built on three concepts:", LF
  db "- Capabilities (access control)", LF
  db "- Fractal Tasks (tree hierarchy)", LF
  db "- Archives (storage)", LF, LF
  db "No PIDs. No signals. No hierarchical FS.", 0
entry1_end:

entry2_data:
  db "color - set text color", LF
  db "help - this help", LF
  db "info - system info", LF
  db "caps - list capabilities", LF
  db "invoke - invoke a capability", LF
  db "tasks - task hierarchy", LF
  db "echo - print text", LF
  db "calc - calculator", LF
  db "clear - clear screen", LF
  db "version - show version", LF
  db "whoami - current user", LF
  db "halt - halt system", 0
entry2_end:

entry3_data:
  db "Aevum OS is released into the", LF
  db "Public Domain. Do whatever you want.", 0
entry3_end:

times 16384-($-$$) db 0
