# 4. Boot Contract and Exception-Level Normalization

![Primary boot flow](diagrams/boot-flow.svg)

## 4.1 There is no universal “Arm boot state”

Arm defines reset and architectural states, but your kernel normally enters through firmware or QEMU loader code. The boot protocol, not the Arm ISA alone, determines:

- which CPU enters first
- initial EL
- MMU state
- cache/coherency state
- register arguments
- where the DTB is
- where the kernel image is loaded
- how secondary CPUs are released

Document these as platform contracts.

## 4.2 Initial platform contracts

### QEMU `virt`

For a non-ELF AArch64 image passed via `-kernel`, QEMU documents:

```text
x0 = DTB physical address
RAM starts at 0x40000000
other device addresses: discover from DTB
```

QEMU's `virt` default CPU is 32-bit Cortex-A15, so an AArch64 run must select a 64-bit CPU [QEMU-VIRT]. Use a fixed initial development command such as:

```sh
qemu-system-aarch64 \
    -machine virt,gic-version=2 \
    -cpu cortex-a72 \
    -smp 4 \
    -m 1G \
    -kernel zig-out/bin/kernel.bin \
    -nographic
```

Do not rely forever on a PL011 hardcoded address even though the current `virt` layout commonly places the first PL011 at `0x09000000`; QEMU explicitly guarantees only a small set of addresses and tells bare-metal guests to use its generated DTB [QEMU-VIRT].

### QEMU Raspberry Pi models

QEMU documents `raspi3b` as four Cortex-A53 cores and `raspi4b` as four Cortex-A72 cores and includes PL011/AUX UART models [QEMU-RASPI]. Treat them as separate platforms from physical boards because the emulator implements only a subset of real peripherals and its boot shim is QEMU code.

### Real Raspberry Pi

Raspberry Pi firmware runs a model-appropriate Arm stub before the kernel; `config.txt` controls kernel selection, 64-bit mode on supported older boards, and related boot behavior [RPI-CONFIG]. Current documentation describes the stub as low-level setup code executed before the kernel.

The public Raspberry Pi `armstub8.S` is especially useful for understanding the handoff: it performs EL3-side setup, `ERET`s to EL2, parks non-primary cores in a `WFE` loop, loads the primary DTB pointer into `x0`, zeros `x1-x3`, and branches to the kernel entry. That validates an initial real-Pi contract of **kernel entry at EL2 with the DTB in x0 and secondaries parked by the stub**, rather than every core racing through `_start` [RPI-ARMSTUB8].

Keep Device Tree enabled. The firmware selects and loads a board DTB, and the kernel relies on it for memory/device topology [RPI-DT].

## 4.3 Initial supported entry EL

The kernel accepts:

```text
EL1 AArch64 -> normalize to EL1h conventions -> continue
EL2 AArch64 -> configure lower EL -> ERET to EL1h -> continue
```

The kernel rejects:

```text
EL0 entry
EL3 entry
AArch32 entry
```

Rejecting EL3 is a scope decision, not an architectural limitation.

## 4.4 Primary entry register preservation

The platform wrapper must not destroy boot arguments. The common entry immediately preserves:

```text
x0    firmware/QEMU boot argument, normally DTB PA under the chosen contract
x1-x3 reserved boot args, preserved until contract validation
MPIDR_EL1
CurrentEL
```

Do not store these into ordinary zero-initialized globals before BSS has been cleared. Keep them in registers or in a linker-defined non-BSS bootstrap record that is never implicitly assumed zero.

A simple primary path can reserve callee-saved registers before calling anything:

```text
x19 = boot x0 / DTB physical address
x20 = MPIDR_EL1
x21 = raw CurrentEL
```

Once the stack and BSS are valid, copy them into a typed `BootInfo`.

## 4.5 DAIF

Mask asynchronous exceptions as one of the first instructions:

```text
D: debug exception mask
A: SError mask
I: IRQ mask
F: FIQ mask
```

Keep IRQ/FIQ masked until at least:

- stack valid
- BSS valid
- `VBAR_EL1` valid
- vector frame verified
- interrupt controller initialized enough to acknowledge sources
- handlers installed

Do not use “the firmware probably left interrupts disabled” as a contract.

## 4.6 Primary boot stack

Before calling Zig:

1. Obtain linker symbol `__boot_stack_top` with a PC-relative sequence.
2. Align it down to 16 bytes if the linker does not already assert alignment.
3. Put it in the correct EL stack register.

If currently EL2, there are two choices:

- temporarily use an EL2 bootstrap SP while preparing EL1, then set `SP_EL1`
- set `SP_EL1` before `ERET`, with the common Zig entry occurring only at EL1

Prefer the second conceptual model: all ordinary kernel code begins at EL1h and uses `SP_EL1`.

## 4.7 EL2 → EL1h normalization

At EL2, configure only enough state to provide a predictable non-hypervisor EL1 environment, then leave EL2.

The exact bit definitions must be taken from the Arm Architecture Reference Manual for the minimum architecture version you support; do not copy unexplained constants from tutorials. The setup normally includes at least the following concepts:

### `HCR_EL2`

Ensure lower ELs execute AArch64:

```text
HCR_EL2.RW = 1
```

Avoid accidentally enabling traps or virtual-machine behavior you do not handle.

### Generic timer access

Configure EL2 timer-control state so EL1 can access the intended architectural counters/timers without trapping to an EL2 handler that does not exist. Arm's EL-transition example explicitly configures timer access before dropping to EL1 [ARM-EL-TRANSITION].

### FP/SIMD traps

Because the initial policy is “kernel does not rely on FP/SIMD until context handling exists,” configure trap state deliberately. Either forbid compiler-generated FP/SIMD in the kernel build or configure access and later implement state preservation. Never leave the policy accidental.

### `SCTLR_EL1`

Put EL1 in a known pre-MMU state rather than inheriting unknown control bits. Do not enable MMU/caches here unless the MMU milestone owns that transition.

### `SP_EL1`

Set the primary kernel stack that EL1h will use.

### `ELR_EL2`

Set to the `el1_entry` label.

### `SPSR_EL2`

Set return state to:

```text
AArch64 EL1h
DAIF masked
```

Then execute:

```asm
eret
```

Arm documents this style of exception-level transition using `HCR_EL2`, `SPSR_EL2`, `ELR_EL2`, and `ERET` [ARM-EL-TRANSITION].

## 4.8 Direct EL1 entry

If already at EL1:

1. Ensure `SPSel` selects `SP_EL1` (`EL1h` stack convention).
2. Set `SP_EL1` to the boot stack if the incoming value is not part of the explicit boot contract.
3. Put EL1 system registers used by early boot into known states.
4. Continue at the same common `el1_entry` label used by the EL2 path.

All subsequent common code should no longer care whether firmware entered at EL1 or EL2 except for diagnostic `BootInfo.entry_el`.

## 4.9 Why not EL3

Dropping from EL3 is mechanically possible, but a correct design must decide:

- secure vs non-secure state
- `SCR_EL3` routing/configuration
- secure GIC state
- FIQ/IRQ/SError routing
- EL2 availability and state
- firmware SMC services
- PSCI ownership or forwarding

That is secure-firmware/monitor work. Keep the kernel contract:

```text
Dagos enters in non-secure AArch64 EL1 or EL2.
```

If direct EL3 reset becomes a goal, implement a distinct boot firmware/monitor layer rather than spreading EL3 assumptions through the kernel.

## 4.10 BSS clearing order

Only after a valid stack exists and only on the boot CPU:

```text
[__bss_start, __bss_end) = 0
```

A robust clear loop:

- requires start/end alignment compatible with the store width
- uses half-open bounds
- never touches `.boot_stack`
- uses no Zig globals before the clear completes

Afterward construct:

```text
BootInfo {
    dtb_phys,
    entry_mpidr,
    entry_el,
    boot_cpu_logical_id (once known),
}
```

## 4.11 Install `VBAR_EL1`

Set `VBAR_EL1` to `__vectors_start`, followed by an `ISB` before relying on the new vector base. `VBAR_EL1` is undefined after reset and must be initialized before exceptions are enabled [ARM-EXC].

Do this before the first deliberate exception test.

## 4.12 First Zig ABI

Define exactly one early function ABI, for example conceptually:

```text
archEarlyMain(dtb_phys, entry_mpidr, entry_el)
```

Assembly passes normal AAPCS64 arguments in `x0-x2` after the architecture is ready for a public function call.

The function may:

- initialize an early console
- validate boot information
- print diagnostics
- run exception smoke tests

It may not allocate from the general heap or enable interrupts.

## 4.13 Secondary CPUs do not repeat primary entry

Do not use `_start` as the normal secondary CPU entry once SMP is implemented. The primary uses firmware/PSCI/spin-table to start a secondary at `secondary_entry_phys`, which runs `secondary.S` and then a dedicated Zig secondary entry.

This prevents a secondary from accidentally:

- clearing BSS
- reparsing global boot state
- reinitializing PMM
- rewriting global page tables
- resetting the console

Secondary CPU design is detailed in [Interrupts, timers, and SMP](08-interrupts-timers-smp.md).
