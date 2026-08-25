# 8. Interrupts, Timers, SMP, and CPU-Local State

![Secondary CPU bring-up](diagrams/smp-flow.svg)

## 8.1 CPU exceptions and interrupt controllers are different layers

The AArch64 vector table tells the kernel that an IRQ exception was taken. The interrupt controller tells the kernel which interrupt source is pending and provides acknowledgement/end-of-interrupt semantics.

Flow:

```text
device raises interrupt
       |
       v
interrupt controller
       |
       v
CPU IRQ exception
       |
       v
EL1 vector +0x280 or +0x480
       |
       v
save ExceptionFrame
       |
       v
generic irqDispatch(frame)
       |
       v
controller acknowledge -> interrupt ID
       |
       v
registered device/timer handler
       |
       v
controller end/deactivate
       |
       v
exception exit / possible reschedule
```

Do not put GIC register accesses in `vectors.S`.

## 8.2 Interrupt-controller interface

An initial architecture-neutral interface needs roughly:

```text
initGlobal()
initCpu(logical_cpu)
enable(irq)
disable(irq)
acknowledge() -> InterruptId
end(InterruptId)
setPriority(...) later
setAffinity(...) later
sendIpi(...) when supported
```

Separate global distributor-like initialization from per-CPU interface initialization because secondary CPUs must perform the latter independently.

## 8.3 Target interrupt controllers

### QEMU `virt`

Force GICv2 initially:

```text
-machine virt,gic-version=2
```

QEMU documents GICv2 as supported and notes the eight-CPU GICv2 limit [QEMU-VIRT]. Four development CPUs fit comfortably.

Do not add GICv3 to the first milestone merely because QEMU supports it. Add it later as a separate driver/architecture exercise.

### Pi 4 / BCM2711

Current Raspberry Pi BCM2711 DTS describes an `arm,gic-400` interrupt controller, i.e. GICv2-family hardware [RPI-BCM2711-DTS].

### Pi 5 / BCM2712

Current BCM2712 DTS also describes `arm,gic-400` for the main interrupt controller [RPI-BCM2712-DTS].

### Pi 3 / BCM2837 family

Pi 3 uses the BCM2836-family local interrupt-controller arrangement in addition to the legacy BCM peripheral interrupt controller. This is not a GICv2 clone. Keep it behind the generic interrupt-controller boundary. Current Raspberry Pi DTS/source material documents the local interrupt controller and CPU-local timer/mailbox interrupt registers [RPI-BCM2836-DTS].

## 8.4 IRQ handler table

Before a heap exists, use a fixed handler table:

```text
IrqHandlerEntry {
    callback,
    context,
    flags,
}

handlers[MAX_INTERRUPT_IDS]
```

The interrupt-controller driver can expose its supported ID range so the generic table size is not silently guessed.

Initial policy:

- one handler per IRQ
- no shared IRQs
- no threaded IRQ handlers
- no allocation in hard IRQ context
- no blocking locks in hard IRQ context

## 8.5 Architectural timer

Use the Arm generic timer as the first scheduling/time source instead of a board-specific peripheral timer.

The architecture exposes a counter frequency and timer/counter registers. The EL2 → EL1 boot path must ensure the intended EL1 timer accesses are not unexpectedly trapped to an EL2 handler that Dagos does not implement [ARM-EL-TRANSITION].

Expose architecture-neutral time APIs:

```text
counterTicks() -> u64
counterFrequencyHz() -> u64
monotonicNanoseconds() -> u64
setOneShotDeadline(deadline_ticks)
cancelTimer()
```

Do not hardcode the counter frequency. Read the architectural frequency register and use checked arithmetic for time conversion.

## 8.6 Timer IRQ discovery

The generic timer interrupt is typically a PPI described in Device Tree. Do not hardcode a single interrupt number across all boards.

The FDT/interrupt-controller binding must translate the timer's interrupt specifier into the controller's logical `InterruptId`/PPI representation.

## 8.7 First IRQ test

Before scheduling:

```text
initialize vectors
initialize GIC/BCM controller
register timer handler
program one-shot timer
unmask IRQ locally
print "waiting"
WFI
IRQ fires
handler acknowledges timer/controller
handler prints/increments counter
ERET
```

Then repeat many times.

Do not debug the first timer IRQ and first context switch simultaneously.

## 8.8 CPU topology

After DT parsing, represent CPUs as:

```text
CpuInfo {
    logical_id,
    hardware_id / MPIDR affinity,
    status,
    enable_method,
    release_address?,
}
```

The raw `MPIDR_EL1` is not the same type as a dense kernel logical CPU ID.

For current Pi boards, low affinity values are simple, but the kernel should still build a mapping rather than spread `MPIDR & 0xff` throughout code.

## 8.9 Secondary startup methods

Represent firmware boot methods explicitly:

```text
CpuBootMethod =
    psci
    spin_table
    platform_specific
```

The Arm64 boot protocol documents PSCI and spin-table as standard secondary CPU mechanisms [ARM64-BOOT].

## 8.10 PSCI

For a CPU whose Device Tree enable method is PSCI, parse the PSCI node to determine the conduit (`smc` or `hvc`) rather than hardcoding one.

The primary conceptually performs:

```text
PSCI CPU_ON(
    target_mpidr,
    secondary_entry_phys,
    context_id
)
```

The entry address is physical because the target CPU may start with translation disabled.

The context value can be used when the firmware/PSCI version guarantees it is delivered according to the PSCI ABI; otherwise the secondary can resolve its logical CPU from MPIDR and a prebuilt topology table.

## 8.11 Spin-table

For `enable-method = "spin-table"`, the CPU node provides `cpu-release-addr` [ARM64-BOOT]. The primary:

1. verifies the release address is reserved and correctly aligned
2. writes `secondary_entry_phys` as a 64-bit little-endian value
3. performs the cache maintenance/order operations required by the boot contract
4. executes `SEV`

Current BCM2711 DTS provides concrete release addresses for its four CPUs, but these are Device Tree data, not generic Pi constants [RPI-BCM2711-DTS].

## 8.12 Secondary trampoline lifetime

`secondary_entry_phys` must remain executable at a physical/identity address until all secondaries have started.

Therefore:

- keep the trampoline in a dedicated linker section
- identity-map it after the MMU is enabled
- do not reclaim that page during early PMM initialization
- remove/reclaim only after CPU bring-up is complete and no hotplug path depends on it

## 8.13 Secondary descriptor

Before starting a CPU, primary prepares immutable/bootstrap information accessible with MMU off:

```text
SecondaryBootInfo {
    expected_mpidr,
    logical_id,
    stack_top_phys,
    kernel_ttbr_phys,
    high_stack_top_va,
    percpu_pointer_va,
}
```

Place this in memory reachable by identity mapping or by physical addresses used by the trampoline.

Do not require the secondary to traverse heap data structures before its MMU and permanent stack exist.

## 8.14 Secondary sequence

A secondary performs:

```text
entry at physical trampoline
    |
    v
mask DAIF
    |
    v
read MPIDR_EL1 and locate SecondaryBootInfo
    |
    v
establish temporary/private aligned stack
    |
    v
normalize to EL1h if boot contract permits variation
    |
    v
set VBAR_EL1 to physical/identity vector address
    |
    v
install MAIR/TCR/TTBR consistent with primary
    |
    v
enable MMU/caches using common architecture routine
    |
    v
branch high
    |
    v
switch to permanent high kernel stack
    |
    v
set high VBAR_EL1
    |
    v
initialize PerCpu pointer
    |
    v
interruptController.initCpu()
    |
    v
per-CPU timer/scheduler state
    |
    v
publish ONLINE with release ordering
    |
    v
idle/scheduler loop
```

Reuse the same AArch64 MMU-enable helpers as the primary. Do not maintain a second set of magic system-register constants in `secondary.S`.

## 8.15 Per-CPU state

Initial structure:

```text
PerCpu {
    logical_id,
    mpidr,
    state,
    current_task,
    idle_task,
    irq_depth,
    preempt_disable_count,
    need_reschedule,
    kernel_stack metadata,
    timer state,
}
```

Start with a global fixed array indexed by `LogicalCpuId`.

Later optimize access using an EL1 thread-ID register or another architectural per-CPU pointer convention, but document ownership before doing so.

## 8.16 CPU state machine

Use explicit states:

```text
Discovered
Prepared
Starting
Online
Offline/Failed
```

Only the primary writes `Prepared/Starting`; each secondary publishes `Online` itself.

Use atomic acquire/release semantics for state publication. Do not use an ordinary volatile integer as an SMP synchronization primitive.

## 8.17 Spinlocks

Implement kernel locks with AArch64 acquire/release semantics.

Minimum API:

```text
lock()
tryLock()
unlock()
```

Then add:

```text
lockIrqSave()
unlockIrqRestore()
```

for data shared with local interrupt handlers.

A local IRQ mask does not stop another CPU. A spinlock does not automatically prevent a local interrupt handler from deadlocking on the same lock. These are separate concerns.

## 8.18 Locking rules

Document lock context for every major lock:

```text
PMM lock             task context only initially
console lock         task + panic bypass; avoid hard IRQ printing normally
scheduler runqueue   IRQ-safe once timer can schedule
process VM lock      task context; page-fault interaction later
```

Introduce a lock-order document once more than a few nested locks exist.

## 8.19 Console under SMP

Ordinary console output becomes serialized by a lock after secondaries are online. Panic output cannot simply block forever on that lock because the panicking CPU may already own it or another stopped CPU may own it.

Panic policy:

```text
mask local IRQ
attempt nonblocking/forced polling console path
emit CPU ID and panic data
stop this CPU
```

Eventually send stop IPIs to other CPUs before dumping global state.

## 8.20 IPIs

Do not require IPIs for the first `hello world` or first secondary bring-up.

They become necessary for:

- scheduler reschedule requests
- TLB shootdown
- stopping CPUs on panic
- cross-CPU work

Pi 3's local mailbox mechanism and GIC SGIs are different hardware implementations behind an IPI abstraction.

## 8.21 TLB shootdown

Once a page mapping used by multiple CPUs is removed or changed, local TLBI is insufficient.

The VMM/page-table subsystem requests a shootdown:

```text
lock/update mapping
publish invalidation request
send IPI to CPUs using address space
remote CPUs execute required TLBI + barriers
acknowledge
initiator completes operation
```

Do not implement this before dynamic SMP mappings need it, but keep ownership in VMM + IPI infrastructure rather than in the PMM.

## 8.22 SMP milestone scope

The first successful SMP kernel only needs:

- discover CPUs
- start all configured secondaries
- private stacks
- shared kernel mappings
- per-CPU state
- synchronized console
- idle loops
- timer/IRQ on each CPU or a deliberately documented subset

Do not combine first SMP with work stealing, CPU hotplug, NUMA, or per-CPU allocators.
