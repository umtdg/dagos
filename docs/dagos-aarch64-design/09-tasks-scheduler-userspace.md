# 9. Tasks, Scheduling, and Userspace

## 9.1 Progression

Use this sequence:

```text
idle context
  -> cooperative kernel tasks
  -> tested context switch
  -> preemptible kernel tasks
  -> process address spaces
  -> EL0 tasks
  -> SVC/syscalls
```

The exception subsystem already supports lower-EL vectors before this phase; this phase gives those vectors real isolated processes to manage.

## 9.2 Context switch is not an exception frame

An exception can interrupt arbitrary code, so its frame saves full architectural state needed to resume that exact point.

A scheduler context switch occurs at a controlled ABI boundary. Under AAPCS64, callee-saved state includes `x19-x29` plus the link register/return structure needed by the switch routine [AAPCS64].

Keep:

```text
ExceptionFrame
```

and:

```text
ContextFrame / saved_sp
```

as separate concepts even if some later scheduler path transfers information between them.

## 9.3 Kernel task structure

Initial conceptual structure:

```text
Task {
    id,
    state,
    saved_sp,
    kernel_stack,
    owner_process?,
    address_space?,
    cpu_affinity?,
    scheduling metadata,
}
```

Initial states:

```text
Unused
Runnable
Running
Blocked
Sleeping
Dead
```

State transitions occur under scheduler synchronization once SMP/preemption exists.

## 9.4 Kernel stacks

Once the MMU exists, allocate stacks dynamically with guard pages:

```text
unmapped guard
RW + NX kernel stack
unmapped guard
```

A 16-KiB initial usable stack is reasonable for development but is kernel policy, not an architecture requirement. Instrument high-water usage before tuning.

Each EL0 task requires a kernel stack because exceptions from EL0 enter EL1 using `SP_EL1`.

## 9.5 `SP_EL1` ownership while a task runs in EL0

Before returning to a user task:

```text
SP_EL1 must reference that task's usable kernel exception stack
SP_EL0 must reference that task's user stack
```

On an EL0 exception, the CPU enters the lower-EL vector and the prologue pushes `ExceptionFrame` on the kernel stack.

When switching to a different user task, its kernel-stack/exception-return context becomes the one associated with `SP_EL1` before `ERET`.

## 9.6 Cooperative scheduler first

Implement:

```text
yield()
```

with a single global round-robin run queue and one lock.

Acceptance test:

```text
task A increments/prints A then yields
task B increments/prints B then yields
repeat for millions of switches
```

Verify callee-saved registers with dedicated torture tests rather than trusting output alone.

## 9.7 Context switch ABI

The assembly switch routine conceptually receives:

```text
switchContext(prev_saved_sp*, next_saved_sp*)
```

and:

1. saves required callee-preserved registers on the current task stack
2. stores current SP through `prev_saved_sp`
3. loads next task SP
4. restores next task's saved registers
5. returns into next task's continuation

Keep the Zig declaration and assembly symbol/calling convention identical.

Do not use SP as if it were a normal general-purpose register in instructions that do not permit it; use a temporary GPR when storing/loading SP values.

## 9.8 Initial kernel task bootstrap

A newly created kernel task has never previously called `switchContext`, so fabricate a stack frame matching the restore sequence.

The synthetic saved `x30` should point to a trampoline such as:

```text
kernelTaskStart
    calls task function
    if it returns -> taskExit
```

Never let a task function return into uninitialized stack memory.

## 9.9 Preemption

After timer IRQs work independently, connect them to scheduling.

Preferred control flow:

```text
timer IRQ
  |
  v
account time / set need_reschedule
  |
  v
common exception exit
  |
  +--> if preemption allowed and runnable task differs: schedule
  |
  v
restore / ERET
```

Do not blindly switch while holding arbitrary IRQ-handler locks.

## 9.10 Preemption disable

Per-CPU state needs a counter rather than a Boolean:

```text
preempt_disable_count
```

Nested critical sections can increment/decrement safely. Underflow is a kernel bug.

A pending reschedule is acted on when the counter returns to zero at a safe boundary.

## 9.11 Idle tasks

Each online CPU owns an idle task that runs when no other task is runnable.

Idle loop eventually uses:

```text
WFI
```

with interrupts configured to wake the CPU. Do not busy-spin permanently once timer/IPI wakeup is reliable.

## 9.12 Process versus task

Keep concepts separate even if one process initially contains one task.

```text
Process:
    address space
    resource namespace/handles later
    process ID

Task/thread:
    execution state
    kernel stack
    scheduler state
    user register state
```

This avoids redesign when multithreading is added.

## 9.13 User process address space

A process owns a TTBR0 root and VM metadata. Kernel TTBR1 mappings are shared.

Initial program layout can be simple:

```text
low user VA
    text      R+X
    rodata    R
    data      R+W
    heap      R+W later
    ...
    guard
    stack     R+W
high user VA
```

All user writable pages are NX unless deliberately executable.

## 9.14 User register state

For a user task, the saved exception frame is a natural complete user register state:

```text
x0-x30
SP_EL0
ELR_EL1
SPSR_EL1
```

Keep scheduler bookkeeping separate from this architectural state.

## 9.15 First EL0 program

Do not begin with ELF loading. Start with a kernel-embedded test blob copied/mapped into a user page.

Program behavior:

```text
set recognizable registers
SVC #0
verify returned x0
attempt another SVC to print a short message
SVC exit
```

Then add deliberate fault programs.

## 9.16 Syscall dispatch

Use a fixed compile-time syscall table initially:

```text
0  debug_write / write
1  exit
2  yield
```

Every syscall validates user pointers through user-copy helpers.

Do not let `write(fd, user_ptr, len)` pass `user_ptr` directly to the UART/console driver.

## 9.17 `copyFromUser`/`copyToUser`

These are kernel memory-safety boundaries.

Initial implementation may prevalidate page-table mappings for the full range, then copy. Later concurrent unmapping/page faults can require stronger address-space locking or fault-fixup mechanisms.

Always check:

```text
start in user VA range
start + len does not overflow
end in user VA range
required permissions
mapping exists for every page
```

## 9.18 User fault handling

For a lower-EL abort:

1. identify current process/task
2. decode `ESR_EL1`
3. capture `FAR_EL1` if valid
4. determine whether the address lies in a valid VM area
5. initially: kill process on any unmapped/protection fault
6. later: resolve demand-zero/file-backed page faults where policy allows

A user process cannot be allowed to panic the entire machine merely by performing an invalid access.

## 9.19 Kernel fault while handling a user syscall

A kernel data abort caused by a bug in syscall code is still a kernel fault. Do not relabel it a user fault because the syscall originated at EL0.

Only explicit user-access fixup machinery may convert a specific EL1 fault into `EFAULT`-like behavior.

## 9.20 FP/SIMD state

Before preemptive user tasks use FP/SIMD, define how `v0-v31`, FPCR, and FPSR are preserved.

Initial safest policy:

- compile kernel to avoid implicit FP/SIMD if toolchain options allow
- prevent/handle EL0 FP use until save/restore exists

Then implement either eager or lazy user FP state management deliberately.

Do not let the compiler begin using vector registers across context switches without a preservation policy.
