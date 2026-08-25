# 11. Debugging, Testing, and Bring-up Procedure

## 11.1 Always retain observability artifacts

Every build should make it easy to inspect:

```text
kernel.elf
kernel.bin
link map
full disassembly
symbol table
selected platform configuration
QEMU command line or generated Pi config.txt
```

When a fault occurs, do not debug from source assumptions alone. Determine the exact faulting machine instruction.

## 11.2 QEMU GDB workflow

Maintain a dedicated debug run mode using QEMU's stop-at-reset/start and GDB server options, conceptually:

```text
-S
-gdb tcp::1234
```

GDB should load `kernel.elf` for symbols even when QEMU boots `kernel.bin`.

Standard questions on every unexplained failure:

```text
What is PC?
What is SP and is it 16-byte aligned?
What is CurrentEL?
What is VBAR_EL1?
What instruction is at PC?
What is ESR_EL1?
What is FAR_EL1?
What is SPSR_EL1?
What are TTBR0/TTBR1/TCR/MAIR/SCTLR after MMU work begins?
Which CPU/MPIDR faulted?
```

## 11.3 Low-level breadcrumbs

Before full panic formatting exists, emit short stage markers through the polling console:

```text
A entry
B el1
C bss
D vectors
E console
F fdt
G mmu tables
H mmu on
```

Do not retain meaningless letters forever. Once output is reliable, replace with named stage messages.

## 11.4 Exception recursion

A dangerous failure pattern:

```text
fault occurs
  -> exception handler prints
     -> console faults
        -> exception handler prints
           -> infinite recursive exception / stack overflow
```

Early exception printing must use the simplest proven polling console path. If console state is suspected, have a no-format emergency byte writer and a GDB-visible halt fallback.

## 11.5 Host-side tests

Pure algorithms should be tested outside the kernel whenever possible:

- address alignment helpers
- half-open range subtraction/merge
- FDT parser using fixture blobs
- endian/cell decoding
- `ranges` translation
- page-table descriptor encode/decode
- virtual-range allocator
- bitmap PMM
- syscall argument range validation

This avoids turning every logic bug into a bare-metal debugging session.

## 11.6 Linker/assembly checks

Automate post-link validation:

```text
_start == expected load VA for identity stage
vector table address % 0x800 == 0
vector size == 0x800
boot stack top % 16 == 0
BSS does not overlap boot stack
kernel physical extent page aligned
secondary trampoline in identity-preserved section
```

Use `readelf`, `objdump`, or Zig/LLVM equivalents in a build verification step.

## 11.7 Exception-frame tests

Create an assembly test that loads recognizable values into many GPRs, triggers `BRK`, lets a special test handler return, then verifies every register.

Example pattern:

```text
x0  = 0x0000...
x1  = 0x1111...
...
x28 = unique pattern
```

Do not use `x29/x30/SP` naively in a way that breaks the calling convention of the test harness. The goal is to verify actual save/restore code, not only frame printing.

## 11.8 MMU fault injection

After permissions exist, deliberately test:

```text
write read-only kernel page
execute NX kernel data page
access unmapped guard page
access unmapped user page from EL0
write user read-only page
EL0 access to privileged kernel VA
```

Each must reach the expected vector/origin and syndrome class.

## 11.9 SMP stress

Once secondaries run:

- boot repeatedly
- have all CPUs increment locked and atomic counters
- verify exact totals
- exercise console serialization
- allocate/free frames from multiple CPUs when PMM becomes SMP-capable
- force scheduler migrations later

A failure that disappears with `-smp 1` is evidence, not a fix.

## 11.10 Platform bring-up procedure

For each new platform:

### Step 1: prove entry

Use debugger if available or a minimal board-specific physical UART write only if necessary.

Verify:

```text
expected physical load address
entry EL
boot argument / DTB pointer
```

### Step 2: reuse shared architecture entry

Do not fork `entry.S` to “make the board boot” unless the difference is genuinely the boot contract.

### Step 3: establish polling PL011

Only platform resource/routing code changes.

### Step 4: deliberate BRK

Prove common vector handling before FDT/MMU work.

### Step 5: parse platform DTB

Compare root compatible, memory, CPU list, UART, interrupt controller with a decompiled DTB.

### Step 6: MMU

Bring up using the same mapping engine but platform-discovered physical resources.

### Step 7: timer/interrupts

Only controller driver and interrupt descriptions should differ materially.

### Step 8: SMP

Use discovered enable method rather than copying another platform's secondary release addresses.

## 11.11 QEMU `virt` as architectural reference target

Use `virt` for fastest iteration on:

- vectors
- EL0/EL1 transitions
- page tables
- GICv2
- generic timer
- PSCI
- scheduler

It is deliberately generic and DT-described [QEMU-VIRT].

Do not let convenient QEMU addresses leak into architecture code.

## 11.12 QEMU Raspberry Pi models as compatibility tests

Use them to exercise BCM-oriented platform paths without hardware reboot cycles, but remember QEMU documents missing devices for the Pi models [QEMU-RASPI]. Passing in QEMU does not prove every real Pi peripheral integration detail.

## 11.13 Real Pi serial electrical requirement

Raspberry Pi UART pins are 3.3 V. Use a 3.3-V USB-UART adapter; do not connect 5-V UART signaling directly [RPI-UART].

The serial adapter is development/debug hardware, not part of the UART controller implementation in the kernel.

## 11.14 Version pinning

Pin/record:

- Zig version
- QEMU version
- Raspberry Pi firmware bundle revision used for SD boot files
- DTB revision/source

`virt` is versioned by QEMU and non-versioned `virt` can evolve across releases [QEMU-VIRT]. For reproducible debugging, record the version even if you continue using `-machine virt` rather than a frozen versioned machine name.

## 11.15 Definition of “hello world works”

Do not count a target complete merely because bytes appeared on UART.

The foundational hello-world target should prove:

```text
correct load address
known EL1h execution
aligned kernel stack
BSS cleared
VBAR_EL1 installed
polling console functional
MPIDR readable
DTB pointer retained
EL1 BRK enters correct vector and dumps valid frame
```

Later “platform foundation complete” adds:

```text
DT parsed
RAM discovered
MMU enabled
interrupt controller works
timer IRQ works
all CPUs online
EL0 SVC/fault path works
```
