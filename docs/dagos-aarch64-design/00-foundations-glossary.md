# 0. Foundations and Glossary

This chapter defines the terms used throughout the design. It is intentionally explicit so later chapters can distinguish architecture requirements from conventions and implementation choices.

Source labels such as `[ARM-EXC]` are defined in [12. References](12-references.md).

## 0.1 Armv8-A, AArch64, and Cortex CPU names

These names describe different things:

```text
Armv8-A / later A-profile architecture
    specification of instructions, registers, exceptions, MMU, etc.

AArch64
    the 64-bit execution state/instruction set of A-profile Arm

AArch32
    the 32-bit execution state/instruction set

Cortex-A53 / A72 / A76
    concrete CPU implementations of compatible architecture revisions
```

Dagos' initial port is AArch64. A future AArch32 port is a separate architecture implementation rather than a `32_bit` switch sprinkled through AArch64 code.

## 0.2 Exception levels

AArch64 software can execute at exception levels:

```text
EL3  secure monitor / highest privileged firmware role
EL2  hypervisor role
EL1  operating-system kernel role
EL0  unprivileged application role
```

Not every implementation must provide every optional higher level. Dagos' initial kernel runs at EL1 and applications run at EL0. It accepts a firmware entry at EL2 and performs a controlled `ERET` to EL1h. It does not initially own EL3 `[ARM-EXC]`.

An EL number is not an interrupt priority. It is a privilege/execution context.

## 0.3 `CurrentEL`, PSTATE, and saved PSTATE

`CurrentEL` tells privileged software which exception level it is executing at.

PSTATE contains current processor state including:

- current EL/mode;
- interrupt masks;
- condition flags;
- other execution-state controls.

When an exception is taken to EL1, hardware saves the old PSTATE into:

```text
SPSR_EL1
```

and saves the exception return PC into:

```text
ELR_EL1
```

`ERET` consumes these saved values to return from the exception `[ARM-EXC]`.

## 0.4 `DAIF`

The four commonly discussed asynchronous mask bits are:

```text
D  debug exceptions
A  SError
I  IRQ
F  FIQ
```

Early boot masks all four. Installing `VBAR_EL1` does **not** automatically make interrupts safe; the relevant interrupt controller, handler state, stack, and CPU-local state must also be initialized before unmasking IRQ/FIQ.

## 0.5 IRQ, FIQ, SError, and synchronous exceptions

AArch64 vectors classify exceptions into four kinds:

```text
synchronous
    directly associated with the current instruction stream:
    SVC, BRK, data abort, instruction abort, undefined instruction, etc.

IRQ
    normal asynchronous interrupt request

FIQ
    fast interrupt request class; routing/use is platform policy

SError
    asynchronous system error, commonly related to external/system memory errors
```

A hardware timer interrupt is an IRQ source. The CPU vector tells Dagos **that an IRQ was taken**; the interrupt controller identifies the interrupt source.

## 0.6 `VBAR_EL1`

`VBAR_EL1` is the base address of EL1's vector table.

EL1's table contains vectors for:

- exceptions from current EL using SP0;
- exceptions from current EL using SPx (`SP_EL1` at EL1);
- exceptions from a lower AArch64 EL;
- exceptions from a lower AArch32 EL.

Thus EL0→EL1 exception support does **not** require `VBAR_EL0`; there is no EL0 vector-base register. EL0 exceptions are handled by the lower-EL entries in the EL1 table `[ARM-EXC]`.

## 0.7 `SP_EL0`, `SP_EL1`, EL1t, and EL1h

AArch64 gives privileged levels stack-selection behavior.

Dagos uses:

```text
EL1h
    kernel execution uses SP_EL1

EL0t
    userspace uses SP_EL0
```

For a user task:

```text
SP_EL0 -> user stack
SP_EL1 -> that task's kernel stack
```

When EL0 takes an exception to EL1, hardware enters the EL1 vector context and Dagos builds its exception frame on the kernel stack. User memory must never be trusted as the kernel's exception stack.

## 0.8 `ESR_EL1` and `FAR_EL1`

`ESR_EL1` is the Exception Syndrome Register for exceptions reported to EL1. Important fields include:

```text
EC   Exception Class: broad reason, e.g. SVC64 or data abort
IL   instruction length information where defined
ISS  class-specific syndrome information
```

`FAR_EL1` is the fault address register for exception classes where a faulting virtual address is reported.

A useful exception dump prints both the raw register and decoded fields. Do not treat `FAR_EL1` as meaningful for every exception class `[ARM-EXC]`.

## 0.9 Physical and virtual addresses

A **physical address (PA)** identifies a location in the physical address space presented to the CPU/memory system.

A **virtual address (VA)** is the address used by software when stage-1 translation is enabled.

Before the MMU is enabled, early Dagos uses an identity-style environment where the linked/executed addresses correspond to physical locations. After the MMU is enabled, PA and VA are different semantic types even if a particular mapping happens to use equal numeric values.

Do not equate:

```text
usize == pointer == physical address
```

`usize` is only a machine-sized integer representation.

## 0.10 MMU and translation tables

The Memory Management Unit translates virtual addresses to physical addresses according to translation tables.

At EL1, key registers include:

```text
TTBR0_EL1   translation-table root conventionally used for lower/user VA
TTBR1_EL1   translation-table root conventionally used for upper/kernel VA
TCR_EL1     translation control: VA size, granules, cacheability, PA size, etc.
MAIR_EL1    named memory-attribute encodings
SCTLR_EL1   includes MMU/cache/control enable fields
```

Dagos initially uses 4-KiB translation granules `[ARM-MM]`.

## 0.11 Page, physical frame, and page-table page

With a 4-KiB granule:

```text
virtual page
    a 4-KiB-sized region of virtual address space

physical frame
    a 4-KiB-sized allocatable unit of physical RAM

page-table page
    a 4-KiB physical frame whose contents are translation descriptors
```

A virtual page is not RAM. It becomes backed when the page-table manager maps it to a physical frame or another physical region.

## 0.12 TLB

A Translation Lookaside Buffer caches translations and related permissions/attributes.

Changing a page-table entry does not imply every CPU immediately forgets an old cached translation. Page-table operations therefore require appropriate:

- descriptor update ordering;
- TLBI operations;
- `DSB`/`ISB` sequences;
- eventually inter-processor TLB shootdowns for mappings cached by another CPU.

The exact sequence depends on the kind of mapping change and is architectural, not a generic compiler-memory-ordering problem `[ARM-MM]`.

## 0.13 Normal memory versus Device memory

RAM and MMIO registers must not use the same memory attributes.

```text
Normal memory
    ordinary RAM; cacheable/shareable attributes can be selected

Device memory
    peripheral-register regions with stronger access/ordering semantics
```

Mapping UART or GIC registers as normal cacheable RAM is a correctness bug.

## 0.14 MMIO and `volatile`

Memory-Mapped I/O means a device exposes control/status registers at addresses in the CPU physical address space.

A PL011 write is conceptually:

```text
CPU store -> mapped UART register -> hardware action
```

Compiler `volatile` semantics are required so accesses are actually emitted as intended. `volatile` is **not** a substitute for Arm memory barriers when architectural ordering is required.

## 0.15 DMB, DSB, and ISB

Very roughly:

```text
DMB  orders relevant memory accesses
DSB  waits for required prior memory/system effects to complete to the selected domain
ISB  flushes/refetches the instruction stream so subsequent instructions observe changed execution context
```

Do not interchange them mechanically. System-register writes such as changing translation/control state have specified synchronization requirements in the Arm ARM.

## 0.16 Cache coherency

SMP CPUs can have private caches while participating in a coherent memory domain. Coherency does not eliminate the need for atomics, locks, acquire/release ordering, TLB shootdowns, or explicit cache maintenance required by firmware/CPU-start protocols.

"The caches are coherent" is not a valid race-condition solution.

## 0.17 Device Tree / FDT / DTB

A **Device Tree** describes hardware as a hierarchy of nodes and properties.

An **FDT/DTB** is the flattened binary representation handed to the kernel.

Important properties/nodes include:

```text
/compatible
/chosen/stdout-path
/memory*/reg
/reserved-memory
/cpus
compatible
reg
ranges
interrupts
interrupt-parent
enable-method
cpu-release-addr
```

FDT integer cells are big-endian. A child's `reg` address is interpreted in its parent bus' address space and may require one or more `ranges` translations before it becomes a CPU physical address `[DT-FLAT] [DT-SPEC]`.

## 0.18 SoC versus board/platform

A SoC such as BCM2711 integrates CPU clusters and peripherals. A board such as Raspberry Pi 4 places that SoC in a concrete machine with firmware configuration and external wiring.

QEMU's `raspi4b` is an emulator platform approximating relevant parts of that machine. It is not proof that every real Pi 4 hardware behavior is emulated.

## 0.19 UART and PL011

UART is a serial communication interface. PL011 is a specific Arm UART controller design.

The generic PL011 driver owns the register-level behavior. The platform/firmware description owns:

- where the PL011 is mapped;
- which instance is intended as the console;
- pin mux/routing;
- clock source/frequency;
- interrupt line.

This is why "UART is platform dependent" is only partly true: the **device instance/integration** is platform dependent while the PL011 device driver is reusable.

## 0.20 Interrupt controller and GIC terms

An interrupt controller collects interrupt sources, applies enable/priority/routing policy, and presents interrupts to CPUs.

For GIC terminology:

```text
SGI  Software Generated Interrupt; commonly used as an IPI
PPI  Private Peripheral Interrupt; per-CPU source such as architectural timer
SPI  Shared Peripheral Interrupt; ordinary shared peripheral source
INTID interrupt identifier
```

GICv2 and GICv3 differ significantly in CPU-interface architecture. Dagos initially forces QEMU `virt` to GICv2 so the first generic GIC path can also serve Pi 4/Pi 5 integration work.

## 0.21 PSCI

PSCI is a firmware interface for power/state coordination, including bringing CPUs online. It can use an `SMC` or `HVC` conduit as described by firmware/Device Tree.

Dagos should not hardcode the conduit. The `/psci` Device Tree description determines how the call is made `[ARM64-BOOT]`.

## 0.22 Spin-table CPU startup

With the spin-table convention, firmware holds a secondary CPU outside normal kernel execution until the primary writes an entry address to a firmware-described release location and performs the required ordering/event operations.

Device Tree can describe this using:

```text
enable-method = "spin-table"
cpu-release-addr = ...
```

`cpu-release-addr` is platform data, not an AArch64 architectural constant `[ARM64-BOOT]`.

## 0.23 `WFE`, `SEV`, and `WFI`

```text
WFE  Wait For Event
SEV  Send Event
WFI  Wait For Interrupt
```

These are architectural instructions, but a complete synchronization protocol requires memory ordering and a shared-state design around them. A `WFE` loop alone does not make a data handoff race-free.

## 0.24 ELF versus flat binary

`kernel.elf` contains:

- sections;
- symbols;
- ELF metadata;
- optional DWARF/debug data.

A flat `kernel.bin` contains selected loadable bytes in image order and has no ELF symbol table.

Boot firmware/QEMU may consume the flat image while GDB uses the ELF. Keep both.

## 0.25 VMA, LMA, and linker `NOLOAD`

In linker terminology:

```text
VMA  virtual/run-time address associated with a section
LMA  load address from which its bytes are loaded, where distinct
```

Initially Dagos keeps these effectively identical to simplify MMU-off bring-up.

`NOLOAD` sections reserve runtime address space but do not require bytes in the flat image. Typical examples:

```text
.bss
boot stacks
bootstrap scratch/page-table reservations
```

Therefore the end of bytes in `kernel.bin` and the end of physical memory reserved by the running kernel are not necessarily the same address.

## 0.26 ABI

An Application Binary Interface defines machine-level interoperability rules. AAPCS64 specifies the AArch64 procedure-call convention used at Zig/assembly boundaries `[AAPCS64]`.

Important initial consequences:

- arguments/results use defined registers;
- x19-x29 have call-preservation roles;
- x30 is the link register;
- SP must obey 16-byte alignment requirements;
- a context switch and an exception frame solve different preservation problems.

## 0.27 Boot stack, kernel stack, and user stack

These are different lifetimes:

```text
boot stack
    temporary primary/secondary bring-up stack before scheduler/task stacks exist

kernel stack
    per scheduled task/thread stack used while that task executes in EL1 or takes EL0 exceptions

user stack
    EL0 virtual-memory stack, referenced through SP_EL0
```

Do not let every CPU share one boot stack. Do not use a user stack as an EL1 exception stack.

## 0.28 Physical allocator, virtual allocator, page mapper, and heap

These are separate:

```text
physical frame allocator
    chooses available RAM frames

virtual range allocator
    chooses unused virtual addresses

page-table manager
    establishes/removes VA -> PA mappings and attributes

heap allocator
    allocates byte/object-sized regions from already usable kernel virtual memory
```

A request for 128 heap bytes may eventually cause all three lower layers to act, but that does not make them one allocator.

## 0.29 Per-CPU state

Per-CPU state belongs to one logical CPU:

```text
logical ID
MPIDR
current task
IRQ nesting/preemption state
scheduler-local state
kernel/idle stack references
interrupt-interface state
```

The kernel maps architectural MPIDR affinity values to dense logical IDs. `MPIDR_EL1 & 0xff` may be a convenient early observation on simple targets but is not the permanent CPU-identity abstraction.

## 0.30 Architecture requirement versus project policy

Every design statement should fall into one of these classes:

```text
architectural requirement
    mandated by Arm architecture/AAPCS

boot-protocol requirement
    promised by the configured firmware/QEMU loader

platform fact
    device integration/address/topology for one target

Dagos policy
    a deliberate project choice, e.g. 4-KiB pages or EL1h

implementation detail
    current code organization/algorithm, replaceable without changing contracts
```

Keeping these categories visible prevents a working QEMU constant from slowly becoming a false "Arm rule".
