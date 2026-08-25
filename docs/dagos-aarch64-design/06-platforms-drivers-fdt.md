# 6. Platforms, Drivers, Early Console, and Device Tree

## 6.1 Target matrix

| Target | CPU | Early serial plan | Interrupt plan | Discovery/boot |
|---|---|---|---|---|
| QEMU `virt` | explicit 64-bit CPU, initially Cortex-A72 | PL011 polling | force GICv2 first | QEMU DTB in `x0` for raw `-kernel` |
| QEMU `raspi3b` | 4× Cortex-A53 | PL011 polling | BCM283x/local controller path | QEMU Pi model |
| QEMU `raspi4b` | 4× Cortex-A72 | PL011 polling | GICv2 / BCM2711 model | QEMU Pi model |
| Pi 3 | 4× Cortex-A53 | PL011 routed to header | BCM local + legacy peripheral IRQ controller | Pi firmware + DT |
| Pi 4 | 4× Cortex-A72 | PL011 routed to header | GIC-400 / GICv2 | Pi firmware + DT / spin-table data |
| Pi 5 | 4× Cortex-A76 | UART10 PL011 debug connector | GIC-400 / GICv2 | Pi firmware + DT |

QEMU documents the CPU models and serial devices for its Pi boards [QEMU-RASPI]. Current Raspberry Pi DTS files describe GIC-400 on BCM2711 and BCM2712 [RPI-BCM2711-DTS], [RPI-BCM2712-DTS].

## 6.2 Early console versus normal console

Keep three concepts separate.

### Early console

Properties:

- polling only
- no heap
- no IRQs
- no scheduler
- no mutex
- base address may come from a platform fallback because DT parsing has not happened yet
- used for bring-up and panic diagnostics

### Serial driver

Device-specific implementation such as PL011.

### Kernel console

Higher-level facility that:

- formats output
- owns locking after SMP
- can select a backend
- may later use interrupts/ring buffers
- provides a panic-safe bypass path

The early and normal console may use the same PL011 instance, but they are different lifecycle states.

## 6.3 PL011 driver boundary

The PL011 driver owns the PrimeCell UART programming model:

- data register
- flags/status
- integer/fractional baud divisors
- line control
- control register
- interrupt masks/status/clear
- FIFO behavior
- polling TX/RX

It receives an instance configuration such as:

```text
Pl011Resources {
    base: MmioRegion,
    input_clock_hz: ?u64,
    irq: ?InterruptSpec,
}
```

Do not put GPIO pin muxing or Bluetooth routing in `pl011.zig`.

## 6.4 MMIO abstraction

Implement narrow MMIO primitives with volatile semantics:

```text
read8 / write8
read16 / write16
read32 / write32
read64 / write64
```

A driver should not duplicate pointer-cast boilerplate in every register accessor.

Volatile access and CPU memory barriers are not the same thing:

- volatile constrains compiler treatment of the access
- `DMB` orders memory observations
- `DSB` waits for relevant memory operations to complete
- `ISB` synchronizes subsequent instruction execution with changed architectural state

Use barriers only where the architecture/device contract requires them; do not sprinkle `DSB SY` after every MMIO write as a substitute for understanding ordering.

## 6.5 Pi 3/4 UART routing

Current Raspberry Pi documentation states that Pi 3 and Pi 4 have both PL011 UART0 and the mini UART, and by default the primary console role on those boards is commonly the mini UART while UART0 is associated with Bluetooth [RPI-UART].

For bare-metal uniformity, make UART0 PL011 the external console through firmware/DT configuration. A practical generated configuration includes:

```ini
enable_uart=1
dtoverlay=disable-bt
```

The Linux instruction to disable `hciuart` is irrelevant to a bare-metal kernel because Linux userspace is not running. The overlay's hardware/DT routing effect is what matters.

## 6.6 Pi 5 early UART

Pi 5 has no mini UART in the same model sense; current Raspberry Pi documentation identifies UART10 as the primary/debug UART on the dedicated debug connector [RPI-UART]. The current BCM2712 DTS describes:

```text
uart10: serial@7d001000
compatible = "arm,pl011", "arm,primecell"
```

and the board DTS enables it [RPI-BCM2712-DTS], [RPI-BCM2712-RPI-DTS].

Use UART10 for the first Pi 5 console. Do not require RP1 PCIe enumeration to print hello world.

## 6.7 Early hardcoded addresses are bootstrap data, not driver data

For first output, each platform may provide a known early PL011 address. Treat it as:

```text
platform.early_console_fallback
```

After FDT parsing, discover the console node and verify that it matches the expected device. If not, either switch console backend deliberately or fail with a clear mismatch.

This lets early boot work before FDT while keeping hardcoded addresses out of reusable drivers.

## 6.8 Initial early-console fallback addresses

For bring-up only, the current Raspberry Pi documentation publishes Linux early-console PL011 CPU-visible addresses that are useful as bare-metal debug cross-checks [RPI-UART]:

```text
Pi 3 PL011 UART0:       0x3f201000
Pi 4 PL011 UART0:       0xfe201000
Pi 5 debug UART10:      0x107d001000
```

For QEMU `virt`, current machine layouts conventionally expose the first PL011 at `0x09000000`, but QEMU explicitly tells guests not to depend on non-guaranteed device addresses. Treat it only as a selected-QEMU-version early fallback and replace/validate it from the generated DTB as soon as the parser works [QEMU-VIRT].

For QEMU Raspberry Pi models, prefer the board model's DTB/SoC description and verify the chosen early address against the emulator version rather than assuming the physical-board address is necessarily the emulator contract.

## 6.8 Why FDT is foundational

QEMU explicitly says that on `virt` only a small part of the physical map is stable enough to hardcode and all other device information should be read from the generated DTB [QEMU-VIRT]. Raspberry Pi firmware also loads board-specific DTBs [RPI-DT].

The kernel needs FDT for:

- RAM ranges
- reserved RAM
- CPU list
- CPU enable methods
- interrupt controller
- UART resources
- bus address translation
- `stdout-path`
- clock references later
- compatible strings

## 6.9 Initial FDT parser constraints

The first parser must be:

```text
read-only
zero-allocation
bounds-checked
endian-correct
iterator/stream oriented
```

Do not build a heap-resident object tree before a heap exists.

## 6.10 DTB header validation

The flattened Device Tree format contains:

- header
- memory reservation block
- structure block
- strings block

with defined alignment and big-endian integer encoding [DT-FLAT].

Validate before walking:

```text
pointer alignment appropriate to access strategy
magic == 0xd00dfeed
totalsize >= header size
totalsize within a configured sane boot maximum
all offsets < totalsize
offset + size checked for overflow and <= totalsize
version compatibility
reservation block 8-byte alignment
structure token alignment
strings offsets in range
node nesting cannot underflow
property length cannot run past structure block
FDT_END exists
```

Treat malformed firmware data as `InvalidDeviceTree`, not as a random load from an unchecked pointer.

## 6.11 Big-endian cells

DTB integer cells are big-endian. The CPU is configured little-endian. Every cell reader must convert explicitly.

Do not cast a property slice directly to `[]const u32` and consume native values without byte swapping.

## 6.12 `#address-cells` and `#size-cells`

`reg` is not universally a pair of 64-bit numbers. Its encoding depends on the parent bus's cell counts [DT-SPEC].

Implement helpers:

```text
readCells(bytes, cell_count) -> checked integer
parseReg(node) -> iterator of bus-relative ranges
```

Handle common one- and two-cell addresses but reject unsupported widths explicitly rather than truncating.

## 6.13 `reg` does not always contain CPU physical addresses

The Devicetree specification defines `reg` in the address space of the **parent bus** [DT-SPEC]. A nested bus can translate addresses through `ranges`.

This is directly relevant to Raspberry Pi peripherals.

Implement:

```text
translateToCpuPhysical(node, bus_address)
```

which walks parent buses and applies `ranges` at each level until reaching root CPU address space.

Never globally define:

```text
UART_BASE = property.reg.address
```

without address translation.

## 6.14 `ranges`

A `ranges` property maps:

```text
child-bus-address -> parent-bus-address for length
```

The parser needs the child bus's address-cell count, the parent's address-cell count, and the child's size-cell count to decode each tuple [DT-SPEC].

For every translation:

1. find the tuple containing the child address
2. calculate offset using checked subtraction/addition
3. reject addresses not covered unless the bus semantics explicitly define identity translation
4. continue at parent

An empty `ranges` property represents an identity mapping for that bus under DT semantics; absence of `ranges` is not always equivalent and should be handled according to the bus binding/specification rather than guessed.

## 6.15 Essential nodes/properties

Implement in this order:

### Root

```text
compatible
model
#address-cells
#size-cells
```

### `/chosen`

```text
stdout-path
bootargs (optional initially)
```

`stdout-path` can contain an alias and optional `:options` suffix [DT-SPEC]. Resolve aliases through `/aliases`.

### memory

```text
device_type = "memory"
reg
```

A DT can contain multiple memory ranges [DT-SPEC]. Do not assume one contiguous `[0, RAM_END)` region.

### reservation block and `/reserved-memory`

Collect both:

- FDT memory reservation entries
- `/reserved-memory` child ranges

The kernel must exclude reserved memory from ordinary allocation [DT-FLAT], [DT-SPEC].

### `/cpus`

Collect:

```text
reg / hardware CPU identifier
status
compatible
enable-method
cpu-release-addr where present
```

Do not assume four CPUs just because the physical Pi models currently have four. QEMU `virt` is configurable with `-smp`.

### interrupt controller

Identify compatible strings and register ranges.

### console UART

Resolve `/chosen/stdout-path`, identify `compatible`, translate `reg`, and capture interrupts/clocks if needed.

## 6.16 DTB lifetime

The parser will initially return slices into firmware-provided DTB memory. Therefore reserve the entire DTB physical range until no references remain.

Initial policy:

```text
reserve original DTB permanently for boot lifetime
```

Later policy may copy it to kernel-owned memory and release the original region.

The DT specification explicitly requires the client not to overwrite the blob before it is finished with it, regardless of whether the firmware included it in the reservation list [DT-FLAT].

## 6.17 Runtime platform validation

Compile-time platform selection determines the expected boot contract. FDT validates the actual machine.

Example:

```text
-Dplatform=rpi5
expected root compatible includes brcm,bcm2712 / Pi 5 board compatible
```

If the actual DT is BCM2837, halt with a platform mismatch. Do not continue using selected-platform hardcoded early resources on the wrong board.

## 6.18 Discovered immutable hardware description

After FDT parsing, convert only the data needed by early kernel subsystems into compact typed descriptions:

```text
DiscoveredPlatform {
    memory_ranges,
    reserved_ranges,
    cpus,
    console,
    interrupt_controller,
    psci?,
}
```

This object is not a clone of the whole Device Tree. Keep the parser available for later driver discovery, but give foundational subsystems typed inputs.

## 6.19 Driver binding

Eventually bind using compatible strings:

```text
"arm,pl011"  -> PL011 driver
"arm,gic-400" -> GICv2 driver
```

Do not begin with a general dynamic driver manager. Compile-time-known driver tables or explicit boot-time matching are enough.

## 6.20 QEMU DTB inspection workflow

Maintain a development target to dump QEMU's DTB and decompile it with `dtc`. The build/run tooling should make it easy to compare:

```text
kernel's parsed RAM ranges
kernel's parsed CPUs
kernel's translated PL011 base
kernel's interrupt controller
```

against the actual generated DTS. This is more reliable than copying memory maps from blogs.
