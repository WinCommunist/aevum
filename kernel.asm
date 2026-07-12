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
    mov ax, 0x0720
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
    mov ax, 0x0720
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
    mov byte [eax+1], 0x07
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
    push eax ebx edx
    mov edi, num_buf+K+15
    mov byte [edi], 0
    dec edi
    mov ebx, 10
    test eax, eax
    jnz .l
    mov byte [edi], '0'
    dec edi
    jmp .d
.l:
    xor edx, edx
    div ebx
    add dl, '0'
    mov [edi], dl
    dec edi
    or eax, eax
    jnz .l
.d:
    inc edi
    mov esi, edi
    pop edx ebx eax
    ret

; ===== Shell =====
shell:
.l:
    mov esi, msg_prompt+K
    call puts
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
    mov edi, tok_halt+K
    call strcmp
    jnz .n11
    call cmd_halt
    jmp .end
.n11:
    mov esi, msg_unknown+K
    call puts
.end:
    call nl
    pop edi esi
    ret

; ===== Command Handlers =====
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
    mov esi, msg_halt+K
    call puts
    cli
.l:
    hlt
    jmp .l

; ===== Splash =====
splash:
    mov esi, msg_splash+K
    call puts
    mov esi, msg_splash2+K
    call puts
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

; ===== Data =====
align 4
cursor_row db 0
cursor_col db 0
shift_f db 0
cmd_len db 0
cmd_buf rb 256
num_buf rb 16

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
dd cap3_name+K, 0
dd cap4_name+K, 0
dd 0

cap1_name db "console", 0
cap2_name db "mem.info", 0
cap3_name db "sys.info", 0
cap4_name db "task.list", 0

; --- Task Table ---
task_list:
db "root        ", 0, 0, 0, 0
db "  shell     ", 0, 0, 0, 0
db "    invoke  ", 0, 0, 0, 0
dd 0

; --- Strings ---
msg_splash db "========================================", LF, 0
msg_splash2 db "       A E V U M   O S   v0.1", LF
db "   Capability-Based Fractal Kernel", LF
db "      Not Unix  /  Not DOS", LF
db "========================================", LF
db "     Type 'help' for commands", LF, 0

msg_info db "=== Aevum OS ===", LF
db "Version: 0.1 (Pre-Alpha)", LF
db "Kernel: Capability-Based Fractal", LF
db "IPC: Message-Oriented via Capabilities", LF
db "Process Model: Task Hierarchy", LF
db "Storage: Archive-Based", LF
db "Not Unix-compatible. Not DOS-compatible.", LF
db "Unique architecture.", LF, 0

msg_help db "Commands:", LF
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
msg_ver db "Aevum OS version 0.1", 0
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

times 8192-($-$$) db 0
