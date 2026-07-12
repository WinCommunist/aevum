# Aevum OS — Manual

## What is Aevum?

**Aevum** (Latin for "eternity, age") is an experimental operating system
with a unique architecture. It is **neither Unix nor DOS** — it has no:

- processes with PIDs
- signals
- hierarchical filesystem
- system calls in the traditional sense

Instead, Aevum uses a **Capability-Based Fractal Kernel** —
a kernel built on three concepts: **capabilities**, **fractal tasks**,
and **archives**.

---

## Building and Running

### Dependencies

- **FASM** — on Windows: `C:\fasm\FASM.EXE`; on Unix-like: must be in `PATH` (`fasm`)
- **QEMU** — for running the OS

### Build

Windows:
```
cd D:\uniq\aevum
build.bat
```

Unix-like:
```
cd D:\uniq\aevum
chmod +x build.sh
./build.sh
```

The script builds:
1. `boot.asm` → `boot.bin` (512 bytes — bootloader)
2. `kernel.asm` → `kernel.bin` (8 KB — kernel)
3. Combines into `aevum.img`

### Run

Windows:
```
run.bat
```

Unix-like:
```
chmod +x run.sh
./run.sh
```

Or manually (any platform):

```
qemu-system-x86_64 -drive file=aevum.img,format=raw -m 64
```

---

## Architecture

### Fractal Kernel

Unlike Unix (where processes are memory-isolated sandboxes)
and DOS (where programs are TSRs hanging in memory), Aevum uses
a **tree-shaped task hierarchy**.

```
root ─┬─ shell ─┬─ invoke
      │         └─ calc
      └─ (worker)
```

Each task can spawn subtasks. Resources are inherited from the parent,
not copied. This is the "fractal" property — the structure repeats
at every level.

### Capability-Based Security

Access to resources (memory, console, system information) goes
**only through capabilities**. No process can access anything
without holding the proper capability.

Built-in system capabilities:

| Capability  | Description                                |
|-------------|--------------------------------------------|
| `console`   | Console access (I/O)                       |
| `mem.info`  | Memory information                         |
| `sys.info`  | System information                         |
| `task.list` | View task tree                             |
| `arc.list`  | List archive entries                       |
| `arc.read`  | Read an archive entry by name              |
| `arc.info`  | Show info about an archive entry           |

The `invoke <name>` command activates a capability. Some capabilities (like `arc.read`, `arc.info`) accept an argument: `invoke arc.read about`.

### Message-Oriented IPC

Tasks communicate through messages (not signals, not pipes).
A message is a structure passed through a capability channel.

---

## Shell Commands

### `help`
Show the command list.

```
aevum$ help
```

### `info`
System information: version, architecture, kernel type.

```
aevum$ info

=== Aevum OS ===
Version: 0.1.2 (Pre-Alpha)
Kernel: Capability-Based Fractal
IPC: Message-Oriented via Capabilities
...
```

### `caps`
List available capabilities.

```
aevum$ caps

Capabilities:
console
mem.info
sys.info
task.list
```

### `invoke <name>`
Invoke a capability by name.

```
aevum$ invoke console
Capability invoked
```

### `tasks`
Show the task tree.

```
aevum$ tasks

Task Hierarchy:
root
  shell
    invoke
```

### `echo <text>`
Print text.

```
aevum$ echo Hello, Aevum!
Hello, Aevum!
```

### `calc <a> <operator> <b>`
Calculator. Operators: `+`, `-`, `*`, `/`.

```
aevum$ calc 5 + 3
8
aevum$ calc 10 / 4
2
aevum$ calc 7 * 6
42
```

### `color <fg> [bg]`
Set text color. Foreground 0–15, background 0–7.

```
aevum$ color 2
aevum$ color 15 1
```

### `clear`
Clear the screen.

### `version`
Show version.

```
aevum$ version
Aevum OS version 0.1.2
```

### `whoami`
Show current user and capability level.

```
aevum$ whoami
guest@aevum (capability level: user)
```

### `halt`
Halt the system.

```
aevum$ halt
System halted.
```

The CPU then enters a `cli; hlt; jmp` loop.
Close the QEMU window or press Ctrl+Alt+2, then type `quit`.

---

## Project Structure

```
D:\uniq\aevum\
├── boot.asm      — bootloader (real mode, INT 13h, PMode switch)
├── kernel.asm    — kernel (protected mode, VGA, keyboard, shell)
├── build.bat     — FASM build script (Windows)
├── build.sh      — FASM build script (Unix-like)
├── run.bat       — QEMU launcher (Windows)
├── run.sh        — QEMU launcher (Unix-like)
├── MANUAL_RU.md  — manual (Russian)
├── boot.bin      — compiled bootloader
├── kernel.bin    — compiled kernel
└── aevum.img     — ready-to-boot disk image
```

### boot.asm (512 bytes)

The bootloader does the following:

1. Saves the boot drive number (`DL → boot_drive`)
2. Sets up the stack
3. Enables A20 (to access addresses > 1 MB)
4. Loads the kernel from disk via INT 13h extensions (LBA, ah=0x42)
5. Jumps to `0x1000:0x0000` (physical address 0x10000)

The kernel is loaded from LBA sector 1 (right after the bootloader),
16 sectors (8192 bytes).

### kernel.asm (8 KB)

The kernel is written for FASM. Structure:

```
 1. Real mode      (setup GDT, enter protected mode)
 2. GDT            (null, code ring0, data ring0)
 3. Protected mode (segment setup, initialization calls)
 4. VGA driver     (putc, puts, clear screen, scroll)
 5. Keyboard       (polling port 0x60, scancode set 1 → ASCII)
 6. Command parser (strcmp, skip_tok, atoi, itoa)
 7. Shell          (read → parse → exec)
 8. Command handlers (help, info, echo, calc, caps, invoke, ...)
 9. Tables         (scancode, capabilities, tasks, strings)
```

#### Internal Design

**Real mode → Protected mode:**
- Kernel is loaded at address 0x10000
- In real mode: set up GDT, set CR0.PE, far jump
- In protected mode: DS=ES=SS=0x10 (flat, base=0), ESP=0x20000

**Display:**
- VGA text mode 80×25, video memory at 0xB8000
- Functions: `putc` (with serial mirroring), `puts`, `clr_scr`, `scroll`
- Cursor updated via VGA ports (0x3D4/0x3D5)

**Keyboard:**
- Poll port 0x64 (bit 0 = output buffer), read 0x60
- Scancode set 1, normal and shift lookup tables
- Supports Shift (L + R), Enter, Backspace, Tab, Space

**Command processing:**
- `strcmp` — compare up to space or null (so `echo hello` ≠ `echohello`)
- `skip_tok` — skip current word
- `skip_spc` — skip spaces
- `atoi` — string → number (modifies ESI, does not restore it)
- `itoa` — number → string (returns ESI pointing to result)

---

## Extending the System

### Adding a command

1. Add a token in the data section:
   ```asm
   tok_mycmd db "mycmd", 0
   ```

2. Add a condition in `exec_cmd`:
   ```asm
   mov edi, tok_mycmd+K
   call strcmp
   jnz .next
   call cmd_mycmd
   jmp .end
   .next:
   ```

3. Write a handler:
   ```asm
   cmd_mycmd:
       mov esi, msg_mycmd+K
       call puts
       ret
   ```

4. Add the message string in the data section.

### Adding a capability

1. Add name and handler to `cap_list`:
   ```asm
   dd cap5_name+K, 0
   ```

2. Define the name:
   ```asm
   cap5_name db "my.cap", 0
   ```

3. Write a handler and put its address instead of `0`.

### Adding a task to the tree

Extend `task_list`:
```asm
db "    mytask    ", 0, 0, 0, 0
dd 0   ; terminating zero
```

Each entry is 16 bytes: name string + null padding.

---

## Key Differences from Unix and DOS

|                | Unix          | DOS           | Aevum                |
|----------------|---------------|---------------|----------------------|
| Processes      | PID, fork/exec| TSR, .EXE     | Task tree (fractal)  |
| Files          | Hierarchical FS | FAT         | Archive-based        |
| Security       | user/group/rwx | None         | Capability-based     |
| IPC            | Pipes, signals| INT, shared   | Message-oriented     |
| Syscalls       | int 0x80 / syscall | INT 21h | Invocation (capability) |
| Memory         | Virtual       | Real/segmented| Flat model (ring 0)  |
| Multitasking   | Preemptive    | Cooperative   | Cooperative          |

---

## Known Limitations

- US QWERTY layout only
- No disk driver — kernel is loaded from a disk image
- No timer/PIT — no preemptive multitasking
- No IDT — exceptions cause triple fault
- No graphics mode — VGA text 80×25 only
- Serial output mirrors VGA (useful for debugging)
- All commands and messages are in English

---

## Source Code Notes

### boot.asm — bootloader

```
org 0x7C00          ; BIOS loads here
DAP:                ; Disk Address Packet for INT 13h ah=0x42
  db 0x10           ; DAP size (16 bytes)
  db 0              ; reserved
  dw 16             ; read 16 sectors
  dw 0x0000         ; buffer offset
  dw 0x1000         ; buffer segment
  dq 1              ; LBA address (sector 1)
```

The bootloader uses extended INT 13h read (ah=0x42),
supported in QEMU, SeaBIOS, and modern hardware.

### kernel.asm — kernel (key constants)

```asm
K = 0x10000    ; kernel base address
VM = 0xB8000   ; VGA text mode buffer
SW = 80        ; screen width
SH = 25        ; screen height
SPORT = 0x3F8  ; COM1 (serial debug)
```

The kernel is assembled with `org 0` and loaded at physical address 0x10000.
All data accesses use `+K` to compensate for flat segmentation
(DS base = 0, but data lives at 0x10000 + offset).

---

## Version History

**v0.1.2 (Pre-Alpha)**
- Archive implementation: `arc.list`, `arc.read`, `arc.info` capabilities
- Archive format (AARC): entries with names stored in kernel memory
- Built-in archive entries: about, philosophy, commands, license
- Capability handler dispatch (invoke now calls handlers)
- Fixed: `color` command no longer crashes with fg > 7 or bg > 7
- Fixed: `color` command now persists across commands (no longer reset by prompt)
- Fixed: prompt preserves user background color
- Fixed: errors/halt restore user color instead of hardcoded 0x07
- Signed number output in `calc` (negative results display correctly)
- 12 commands

**v0.1.1 (Pre-Alpha)**
- Color support (VGA text attributes, `color` command)
- Updated splash screen with colors

**v0.1 (Pre-Alpha)**
- BIOS boot, protected mode switch
- VGA text mode 80×25
- Polling keyboard (US layout)
- Shell with capability-based architecture
- 11 commands
- Debug via COM1 (serial port)

---

*"Beyond Unix. Beyond DOS. Aevum."*
