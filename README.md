# Aevum OS

**Neither Unix. Neither DOS. Aevum.**

Aevum is an experimental operating system with a **Capability-Based Fractal Kernel** — a kernel built on capabilities, fractal tasks, and archives. No processes with PIDs, no signals, no hierarchical filesystem in the traditional sense.

---

## Quick Start

### Dependencies

- **FASM** (Flat Assembler) — Windows: `C:\fasm\FASM.EXE`, Unix-like: `fasm` in `PATH`
- **QEMU** — `qemu-system-x86_64`

### Build & Run

**Windows:**

```
build.bat
run.bat
```

**Unix-like:**

```
chmod +x build.sh run.sh
./build.sh
./run.sh
```

This produces `aevum.img` — a bootable floppy image with a 512-byte bootloader and an 8 KB kernel. The kernel boots into protected mode, initializes VGA text mode (80×25), a polling keyboard driver, and a shell with 13 commands (including `run` for executing embedded programs).

---

## Project Files

| File | Purpose |
|------|---------|
| `boot.asm` | Bootloader (real mode, INT 13h, A20, PMode switch) |
| `kernel.asm` | Kernel (PMode, VGA, keyboard, shell, 13 commands) |
| `build.bat` / `build.sh` | FASM assembly scripts |
| `run.bat` / `run.sh` | QEMU launcher scripts |
| `MANUAL.md` | Full manual (English) |
| `MANUAL_RU.md` | Full manual (Russian) |

---

*https://github.com/WinCommunist/aevum*

---

# Aevum OS

**Ни Unix. Ни DOS. Aevum.**

Aevum — экспериментальная операционная система с **фрактальным ядром на возможностях (Capability-Based Fractal Kernel)**. Никаких процессов с PID, сигналов или иерархической файловой системы в привычном смысле.

---

## Быстрый старт

### Зависимости

- **FASM** (Flat Assembler) — Windows: `C:\fasm\FASM.EXE`, Unix-like: `fasm` в `PATH`
- **QEMU** — `qemu-system-x86_64`

### Сборка и запуск

**Windows:**

```
build.bat
run.bat
```

**Unix-like:**

```
chmod +x build.sh run.sh
./build.sh
./run.sh
```

Результат — `aevum.img`: загрузочный образ дискеты с загрузчиком (512 байт) и ядром (8 КБ). Ядро загружается в защищённый режим, инициализирует VGA text mode (80×25), клавиатуру (опрос) и оболочку с 13 командами (включая `run` для запуска программ).

---

## Файлы проекта

| Файл | Назначение |
|------|-----------|
| `boot.asm` | Загрузчик (real mode, INT 13h, A20, переход в PMode) |
| `kernel.asm` | Ядро (PMode, VGA, клавиатура, shell, 13 команд) |
| `build.bat` / `build.sh` | Скрипты сборки (FASM) |
| `run.bat` / `run.sh` | Скрипты запуска (QEMU) |
| `MANUAL.md` | Полный мануал (английский) |
| `MANUAL_RU.md` | Полный мануал (русский) |

---

*https://github.com/WinCommunist/aevum*
