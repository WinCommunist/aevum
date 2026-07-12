# Aevum OS — мануал

## Что такое Aevum?

**Aevum** (лат. «вечность, эпоха») — экспериментальная операционная система
с уникальной архитектурой. Она **не Unix** и **не DOS** — в ней нет:

- процессов с PID
- сигналов
- плоской файловой системы
- системных вызовов в привычном смысле

Вместо этого Aevum использует **Capability-Based Fractal Kernel** —
ядро, построенное на трёх концепциях: **возможности** (capabilities),
**фрактальные задачи** (fractal tasks) и **архивы** (archives).

---

## Сборка и запуск

### Зависимости

- **FASM** — на Windows: `C:\fasm\FASM.EXE`; на Unix-like: должен быть в `PATH` (`fasm`)
- **QEMU** — для запуска

### Сборка

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

Скрипт собирает:
1. `boot.asm` → `boot.bin` (512 байт — загрузчик)
2. `kernel.asm` → `kernel.bin` (8 КБ — ядро)
3. Объединяет в `aevum.img`

### Запуск

Windows:
```
run.bat
```

Unix-like:
```
chmod +x run.sh
./run.sh
```

Или вручную (любая платформа):

```
qemu-system-x86_64 -drive file=aevum.img,format=raw -m 64
```

---

## Архитектура

### Фрактальное ядро

В отличие от Unix (где процессы — это «песочницы» с изоляцией памяти)
и DOS (где программы — это TSR, висящие в памяти), Aevum использует
**древовидную иерархию задач**.

```
root ─┬─ shell ─┬─ invoke
      │         └─ calc
      └─ (worker)
```

Каждая задача может порождать подзадачи. Ресурсы наследуются от родителя,
а не копируются. Это и есть «фрактальность» — структура повторяется
на каждом уровне.

### Capability-Based Security

Доступ к ресурсам (память, консоль, информация о системе) идёт
**только через возможности** (capabilities). Никакой процесс не может
получить доступ к чему-либо, если у него нет соответствующей
возможности.

Системные возможности (встроенные в ядро):

| Возможность | Описание |
|-------------|----------|
| `console`   | Доступ к консоли (ввод/вывод) |
| `mem.info`  | Информация о памяти |
| `sys.info`  | Информация о системе |
| `task.list` | Просмотр дерева задач |
| `arc.list`  | Список записей архива |
| `arc.read`  | Чтение записи архива по имени |
| `arc.info`  | Информация о записи архива |

Команда `invoke <имя>` активирует возможность. Некоторые возможности (например, `arc.read`, `arc.info`) принимают аргумент: `invoke arc.read about`.

### Message-Oriented IPC

Задачи общаются через сообщения (не сигналы, не пайпы).
Сообщение — это структура, передаваемая через канал возможностей.

---

## Команды оболочки

### `help`
Показать список команд.

```
aevum$ help
```

### `info`
Информация о системе: версия, архитектура, тип ядра.

```
aevum$ info

=== Aevum OS ===
Version: 0.1.2.1 (Pre-Alpha)
Kernel: Capability-Based Fractal
IPC: Message-Oriented via Capabilities
...
```

### `caps`
Список доступных возможностей (capabilities).

```
aevum$ caps

Capabilities:
console
mem.info
sys.info
task.list
```

### `invoke <имя>`
Вызвать возможность по имени.

```
aevum$ invoke console
Capability invoked
```

### `tasks`
Показать дерево задач.

```
aevum$ tasks

Task Hierarchy:
root
  shell
    invoke
```

### `echo <текст>`
Вывести текст.

```
aevum$ echo Hello, Aevum!
Hello, Aevum!
```

### `calc <a> <оператор> <b>`
Калькулятор. Операторы: `+`, `-`, `*`, `/`.

```
aevum$ calc 5 + 3
8
aevum$ calc 10 / 4
2
aevum$ calc 7 * 6
42
```

### `color <fg> [bg]`
Установить цвет текста. Цвет символов 0–15, фон 0–7.

```
aevum$ color 2
aevum$ color 15 1
```

### `clear`
Очистить экран.

### `version`
Показать версию.

```
aevum$ version
Aevum OS version 0.1.2
```

### `whoami`
Показать текущего пользователя и уровень возможностей.

```
aevum$ whoami
guest@aevum (capability level: user)
```

### `halt`
Остановить систему.

```
aevum$ halt
System halted.
```

После этого процессор входит в цикл `cli; hlt; jmp`.
Закройте окно QEMU или нажмите Ctrl+Alt+2, затем `quit`.

---

## Структура проекта

```
D:\uniq\aevum\
├── boot.asm      — загрузчик (режим реальный, INT 13h, переход в PMode)
├── kernel.asm    — ядро (защищённый режим, VGA, клавиатура, shell)
├── build.bat     — сборка через FASM (Windows)
├── build.sh      — сборка через FASM (Unix-like)
├── run.bat       — запуск в QEMU (Windows)
├── run.sh        — запуск в QEMU (Unix-like)
├── boot.bin      — скомпилированный загрузчик
├── kernel.bin    — скомпилированное ядро
└── aevum.img     — готовый образ дискеты
```

### boot.asm (512 байт)

Загрузчик делает следующее:

1. Сохраняет номер загрузочного диска (`DL → boot_drive`)
2. Устанавливает стек
3. Включает A20 (чтобы был доступен адрес > 1 МБ)
4. Загружает ядро с диска через INT 13h extensions (LBA, ah=0x42)
5. Прыгает на `0x1000:0x0000` (физический адрес 0x10000)

Ядро загружается с LBA-сектора 1 (сразу после загрузчика),
16 секторов (8192 байт).

### kernel.asm (8 КБ)

Ядро написано для FASM. Структура:

```
 1. Реальный режим  (setup GDT, Enter protected mode)
 2. GDT             (null, code ring0, data ring0)
 3. Защищённый режим (настройка сегментов, вызов инициализации)
 4. VGA-драйвер     (putc, puts, clear screen, scroll)
 5. Клавиатура      (polling port 0x60, scancode set 1 → ASCII)
 6. Парсер команд   (strcmp, skip_tok, atoi, itoa)
 7. Shell           (read → parse → exec)
 8. Хендлеры команд (help, info, echo, calc, caps, invoke, ...)
 9. Таблицы         (scancode, capabilities, tasks, strings)
```

#### Внутреннее устройство

**Реальный режим → защищённый:**
- Ядро загружается по адресу 0x10000
- В реальном режиме: настройка GDT, включение CR0.PE, far jump
- В защищённом: DS=ES=SS=0x10 (flat, base=0), ESP=0x20000

**Экран:**
- VGA text mode 80×25, видеопамять 0xB8000
- Функции: `putc` (с serial-дублированием), `puts`, `clr_scr`, `scroll`
- Курсор обновляется через порты VGA (0x3D4/0x3D5)

**Клавиатура:**
- Опрос порта 0x64 (bit 0 = output buffer), чтение 0x60
- Scancode set 1, таблицы нормальной и shift-раскладки
- Поддержка Shift (L + R), Enter, Backspace, Tab, Space

**Обработка команд:**
- `strcmp` — сравнение до пробела или нуля (чтобы `echo hello` ≠ `echohello`)
- `skip_tok` — пропустить текущее слово
- `skip_spc` — пропустить пробелы
- `atoi` — строка → число (модифицирует ESI, не восстанавливает)
- `itoa` — число → строка (возвращает ESI на результат)

---

## Расширение системы

### Добавление команды

1. Добавить токен в секцию данных:
   ```asm
   tok_mycmd db "mycmd", 0
   ```

2. Добавить условие в `exec_cmd`:
   ```asm
   mov edi, tok_mycmd+K
   call strcmp
   jnz .next
   call cmd_mycmd
   jmp .end
   .next:
   ```

3. Написать хендлер:
   ```asm
   cmd_mycmd:
       mov esi, msg_mycmd+K
       call puts
       ret
   ```

4. Добавить строку в секцию данных.

### Добавление capability

1. Добавить имя и хендлер в `cap_list`:
   ```asm
   dd cap5_name+K, 0
   ```

2. Определить имя:
   ```asm
   cap5_name db "my.cap", 0
   ```

3. Написать хендлер и указать его адрес вместо `0`.

### Добавление задачи в дерево

Дополнить `task_list`:
```asm
db "    mytask    ", 0, 0, 0, 0
dd 0   ; терминирующий ноль
```

Каждая запись — 16 байт: строка имени + нули.

---

## Принципиальные отличия от Unix и DOS

|                | Unix          | DOS           | Aevum                |
|----------------|---------------|---------------|----------------------|
| Процессы       | PID, fork/exec| TSR, .EXE     | Task tree (fractal)  |
| Файлы          | Иерархическая ФС | FAT        | Archive-based        |
| Безопасность   | user/group/rwx | Нет           | Capability-based     |
| IPC            | Pipes, signals| INT, shared   | Message-oriented     |
| Системные вызовы| int 0x80 / syscall | INT 21h | Invocation (capability) |
| Память         | Virtual memory| Real/segmented| Flat model (ring 0)  |
| Многозадачность| Preemptive    | Cooperative   | Cooperative          |

---

## Известные ограничения

- Только US QWERTY-раскладка
- Нет драйвера дисков — ядро загружается с образа
- Нет таймера/PIT — нет preemptive multitasking
- Нет IDT — исключения вызовут triple fault
- Нет графического режима — только VGA text 80×25
- Serial-вывод дублирует VGA (полезно для отладки)
- Все команды и сообщения на английском (кроме этого мануала)

---

## Исходный код

### boot.asm — загрузчик

```
org 0x7C00          ; BIOS загружает сюда
DAP:                ; Disk Address Packet для INT 13h ah=0x42
  db 0x10           ; размер DAP (16 байт)
  db 0              ; резерв
  dw 16             ; читать 16 секторов
  dw 0x0000         ; смещение буфера
  dw 0x1000         ; сегмент буфера
  dq 1              ; LBA-адрес (сектор 1)
```

Загрузчик использует расширенное чтение INT 13h (ah=0x42),
которое поддерживается в QEMU, SeaBIOS и на современном железе.

### kernel.asm — ядро (ключевые константы)

```asm
K = 0x10000    ; базовый адрес ядра
VM = 0xB8000   ; VGA text mode buffer
SW = 80        ; ширина экрана
SH = 25        ; высота экрана
SPORT = 0x3F8  ; COM1 (отладка через serial)
```

Ядро компонуется с `org 0` и загружается по физическому адресу 0x10000.
Все обращения к данным идут через `+K`, чтобы скомпенсировать
flat-сегментацию (DS base = 0, а данные лежат по адресу 0x10000 + offset).

---

## История версий

**v0.1.2.1 (Pre-Alpha)**
- Реализация архивов: возможности `arc.list`, `arc.read`, `arc.info`
- Формат AARC: записи с именами в памяти ядра
- Встроенные записи: about, philosophy, commands, license
- Диспетчеризация capability-обработчиков (invoke вызывает хендлеры)
- Ядро увеличено до 16 КБ для размещения архива
- Загрузчик читает 32 сектора

**v0.1.2 (Pre-Alpha)**
- Исправлено: команда `color` больше не вызывает сбой с fg > 7 или bg > 7
- Исправлено: `color` теперь сохраняется между командами (промпт больше не сбрасывает)
- Исправлено: промпт сохраняет фон пользователя
- Исправлено: ошибки/halt восстанавливают цвет пользователя
- Вывод знаковых чисел в `calc` (отрицательные результаты отображаются корректно)
- 12 команд

**v0.1.1 (Pre-Alpha)**
- Поддержка цветов (VGA text attributes, команда `color`)
- Цветной экран приветствия (splash)

**v0.1 (Pre-Alpha)**
- Загрузка с BIOS, переход в protected mode
- VGA text mode 80×25
- Polling-клавиатура (US layout)
- Shell с capability-based архитектурой
- 11 команд
- Отладка через COM1 (serial port)

---

*«Beyond Unix. Beyond DOS. Aevum.»*
