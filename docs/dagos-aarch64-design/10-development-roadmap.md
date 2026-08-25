# 10. Development Roadmap and Acceptance Criteria

Each milestone ends in a known-good kernel. Do not begin the next milestone while unexplained faults remain in the previous one.

## M0 — Build contract

Implement:

- AArch64 freestanding Zig target
- platform enum
- platform-selected boot assembly
- platform-selected linker fragment
- common AArch64 linker layout
- ELF + raw binary output
- map + disassembly output
- QEMU normal and GDB run commands

Acceptance:

```text
GDB stops at _start
PC equals selected platform's load address
symbol addresses match map file
SP has not yet been assumed valid before initialization
```

Matrix first: QEMU `virt` only.

## M1 — Raw entry, stack, BSS

Implement:

- platform `_start` wrapper
- shared AArch64 entry
- DAIF masking
- primary boot stack
- preserved boot registers
- BSS clear excluding boot stack
- call into a minimal Zig function

Acceptance in GDB:

```text
SP % 16 == 0
BSS globals are zero
active stack lies outside BSS clear range
x0 boot argument was preserved
Zig function entry reached
```

## M2 — EL normalization

Implement:

- `CurrentEL` decode
- EL2 → EL1h path
- direct EL1h path
- explicit unsupported EL labels
- known `SPSel`/`SP_EL1`

Acceptance:

```text
ordinary kernel code always observes CurrentEL == EL1
entry_el remains recorded separately
DAIF still masked
```

Test QEMU variants that enter under both supported modes if practical.

## M3 — Early polling console

Implement:

- MMIO primitive
- PL011 polling TX
- platform early-console resource
- primitive hex/decimal formatting without heap

Print:

```text
platform
entry EL
current EL
MPIDR_EL1
kernel physical range
boot stack range
DTB PA if provided
hello world
```

Acceptance:

- stable output over thousands of boots
- no interrupt dependency
- no allocator dependency

Bring up in order:

1. QEMU `virt`
2. QEMU `raspi3b`
3. QEMU `raspi4b`
4. Pi 3
5. Pi 4
6. Pi 5

Do not change the generic PL011 driver for each platform; change resource/routing setup.

## M4 — Full EL1 vector table

Implement:

- all 16 slots
- generated exception-frame offsets
- full GPR frame
- current-EL synchronous dispatcher
- lower-EL AArch64 dispatcher path even though no isolated process exists yet
- fatal paths for unsupported origins
- common epilogue/`ERET`

Test:

```text
BRK at EL1 -> correct current-EL sync vector
```

Acceptance:

- x0-x30 preserved across a recoverable deliberate test path
- frame alignment correct
- syndrome decode correct
- vector slot reported correctly
- no recursive panic due to broken console

## M5 — Optional EL0 architectural smoke test

This is optional before the MMU and must be labeled **non-isolated** if translation is disabled.

Purpose only:

```text
prove EL1 -> EL0t -> SVC -> lower-A64 EL1 vector -> ERET
```

Do not call this userspace security. Remove/disable it after the exception mechanics are validated.

If you prefer never to execute unisolated EL0, skip this and perform the same smoke test after M10/M11.

## M6 — Zero-allocation FDT parser

Implement:

- header validation
- big-endian cell readers
- structure iterator
- strings lookup
- root cell counts
- `reg`
- `ranges`
- aliases
- `/chosen/stdout-path`
- `/memory`
- reservations
- `/cpus`
- compatible matching

Acceptance on QEMU:

```text
parsed RAM exactly matches -m
parsed CPU count exactly matches -smp
console compatible/base matches dumped DTS
interrupt controller matches DTS
```

Keep a dumped/decompiled QEMU DTB in test fixtures for host-side parser tests if licensing/project policy allows.

## M7 — Runtime platform validation

Implement:

- expected compatible list per selected platform
- discovered console validation
- discovered interrupt-controller description
- discovered CPU boot methods

Acceptance:

- correct platform boots
- intentionally booting the wrong platform image fails loudly before MMU/device initialization

## M8 — Physical memory map + early page allocator

Implement:

- normalized half-open RAM ranges
- reservation subtraction
- kernel/DTB reservation
- monotonic 4-KiB allocator
- allocation ledger

Acceptance:

- every returned page is aligned
- no returned page intersects any reservation
- exhausts cleanly
- checked arithmetic catches malformed ranges

## M9 — Identity MMU

Implement:

- page-table descriptors
- table creation
- MAIR
- TCR
- TTBR
- SCTLR enable sequence
- identity Normal mappings for RAM/kernel
- Device mapping for UART

Acceptance:

```text
kernel continues after enabling MMU
UART still prints
EL1 BRK still produces correct frame
known RAM read/write works
```

Do not add high-half transition until this is boring and reliable.

## M10 — High-half kernel + direct map

Implement:

- kernel upper-half mapping
- direct physical map
- high virtual stack
- high `VBAR_EL1`
- RX/RW/NX section permissions
- preserve identity secondary trampoline

Acceptance:

```text
PC in configured high range
SP in high range
vector base high
kernel image physical reservation unchanged
physical-to-direct-map round trips pass
write to .text faults
execute from .data faults when tested safely
```

## M11 — Real PMM

Implement bitmap frame allocator.

Acceptance:

- host-side randomized allocator tests
- allocate all free frames: no duplicate
- reserved frame never returned
- free/reallocate works
- early allocations remain reserved

## M12 — Kernel VMM + heap

Implement:

- kernel virtual range allocator
- map/unmap
- dynamic kernel stacks with guards
- general heap

Acceptance:

- multi-page allocations survive stress
- guard page deliberate access faults
- unmap removes access after correct TLB maintenance

## M13 — Interrupt controller

Implement first on QEMU `virt` with GICv2.

Then:

- Pi 4 GICv2
- Pi 5 GICv2
- Pi 3 BCM interrupt path

Acceptance:

- acknowledge/end cycle correct
- spurious/no-pending condition handled
- IRQ mask/unmask works
- no device-specific logic in vector assembly

## M14 — Architectural timer

Implement:

- counter/frequency
- timer PPI discovery
- one-shot timer
- generic IRQ handler

Acceptance:

- repeated timed wakeups
- measured intervals approximately correct using counter frequency
- IRQ can interrupt EL1 safely

## M15 — SMP topology and secondary bring-up

Implement:

- CPU list from DT
- logical ID mapping
- PSCI path
- spin-table path
- secondary physical trampoline
- per-CPU stack/state
- CPU-side interrupt init
- online state atomics
- synchronized console

Acceptance:

```text
all discovered CPUs reach Online
unique stack per CPU
unique PerCpu record per CPU
current EL == EL1 on each
VBAR valid on each
repeated boot stress does not race
```

## M16 — Kernel tasks and cooperative switch

Implement:

- Task
- dynamic guarded kernel stacks
- synthetic initial context frame
- context switch
- round-robin run queue
- `yield`

Acceptance:

- millions of cooperative switches
- register torture test
- task return reaches `taskExit` rather than garbage

## M17 — Preemption

Connect timer to `need_reschedule` and exception exit.

Acceptance:

- a task that never yields cannot starve another runnable task
- scheduler never switches while preemption is disabled
- IRQ nesting/preemption counters remain consistent

## M18 — Process TTBR0 address spaces

Implement:

- per-process page-table root
- user VM ranges
- user text/data/stack mappings
- kernel TTBR1 shared mapping
- address-space activation
- TLB handling

Acceptance without EL0:

- create/destroy many process address spaces
- translate expected user mappings
- kernel address remains privileged-only

## M19 — Real EL0 entry and exception return

Implement:

- `SP_EL0`
- task `SP_EL1`
- `ELR_EL1`
- `SPSR_EL1 = EL0t` policy
- user entry `ERET`

Test:

```text
EL0 SVC -> +0x400 lower-A64 sync vector
EL0 invalid load -> lower-EL data abort
EL0 IRQ -> +0x480 lower-A64 IRQ vector
```

Acceptance:

- syscall returns to next user instruction correctly
- user stack unchanged except user actions
- kernel stack frame balanced
- invalid user access does not panic kernel

## M20 — Initial syscalls

Implement:

```text
write/debug_write
exit
yield
```

plus user-copy helpers.

First real program:

```text
write("hello from EL0\n")
exit(0)
```

Acceptance:

- bad user pointer returns process-visible error or kills process by defined policy
- normal syscall cannot directly hand user pointer to driver
- exiting task is never scheduled again

## M21 — SMP scheduling

Only after single-runqueue correctness:

- per-CPU idle tasks
- choose global runqueue first
- timer scheduling on multiple CPUs
- migration under one scheduler lock

Acceptance:

- no task runs on two CPUs simultaneously
- runqueue invariants hold under stress
- lock/IRQ ordering validated

## Deferred work

Do not make foundational milestones depend on:

```text
filesystem/VFS
block storage
USB
network stack
PCIe/RP1
ELF dynamic linking
demand paging
copy-on-write
signals
advanced scheduler classes
GICv3
CPU hotplug
EL2 virtualization
EL3 secure monitor
AArch32
```
