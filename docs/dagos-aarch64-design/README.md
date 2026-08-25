# Dagos AArch64 Kernel Architecture and Development Design

This document set is the development design for a freestanding Zig kernel targeting AArch64 on:

- QEMU `virt`
- QEMU `raspi3b`
- QEMU `raspi4b`
- Raspberry Pi 3
- Raspberry Pi 4
- Raspberry Pi 5

The initial architecture port is **AArch64 only**. AArch32 is intentionally outside the initial scope. EL0 is **inside** the initial architecture: the EL1 vector table, exception frame, kernel-stack rules, and exception dispatcher are designed from the start for exceptions from AArch64 EL0 to EL1. Actual isolated user processes are enabled only after the MMU and per-process address-space work exists.

## Reading order

1. [Foundations and glossary](00-foundations-glossary.md)
2. [Architecture boundaries and invariants](01-architecture-boundaries.md)
3. [Project and assembly structure](02-project-structure.md)
4. [Build, images, and linker scripts](03-build-linker-images.md)
5. [Boot contract and exception-level normalization](04-boot-and-exception-levels.md)
6. [Exceptions, EL0 → EL1, syscalls, and fault return](05-exceptions-and-el0.md)
7. [Platforms, drivers, early console, and Device Tree](06-platforms-drivers-fdt.md)
8. [MMU, physical memory, virtual memory, and allocators](07-mmu-and-memory.md)
9. [Interrupts, timers, SMP, and CPU-local state](08-interrupts-timers-smp.md)
10. [Tasks, scheduling, and userspace](09-tasks-scheduler-userspace.md)
11. [Development milestones and acceptance criteria](10-development-roadmap.md)
12. [Debugging, testing, and bring-up procedure](11-debugging-testing.md)
13. [Assembly blueprints](13-assembly-blueprints.md)
14. [Per-target boot and bring-up contracts](14-target-contracts.md)
15. [References](12-references.md)

## Diagrams

- [Layering](diagrams/layers.svg)
- [Primary boot flow](diagrams/boot-flow.svg)
- [EL0 → EL1 exception flow](diagrams/el0-exception-flow.svg)
- [Memory-management layering](diagrams/memory-flow.svg)
- [Secondary CPU bring-up](diagrams/smp-flow.svg)

## Foundational dependency chain

```text
platform boot contract
        │
        v
AArch64 entry + known stack + EL1h
        │
        v
BSS + VBAR_EL1 + lower-EL-aware vector table
        │
        v
polling early console
        │
        v
reliable synchronous exception handling
        │
        v
Device Tree parser + actual RAM/device discovery
        │
        v
early physical-page allocator
        │
        v
translation tables + MMU + kernel mappings
        │
        v
physical frame allocator + kernel VMM + heap
        │
        v
interrupt controller + architectural timer
        │
        v
secondary CPU bring-up + SMP synchronization
        │
        v
kernel tasks + context switching + scheduler
        │
        v
per-process TTBR0 address spaces
        │
        v
AArch64 EL0 + SVC + userspace faults
```

## Scope decision

EL3 ownership is not part of the initial kernel. The supported kernel-entry contract is non-secure AArch64 EL1 or EL2, with EL2 normalized to EL1h. Taking ownership at EL3 would turn the project into both a kernel and secure firmware/monitor implementation and would add secure-state, exception routing, and firmware-service responsibilities unrelated to the initial OS goals.

The architectural exception subsystem nevertheless supports the complete EL1 vector-table shape from the beginning: current-EL SP0, current-EL SPx, lower-EL AArch64, and lower-EL AArch32 slots all exist. Unsupported origins fail explicitly rather than falling through into adjacent vector slots.
