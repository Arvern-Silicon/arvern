<p align="center">
  <img src="../doc/img/aRVern_light.png" alt="aRVern" width="180">
</p>

# aRVern core support library

*CSR access and a small trap / interrupt layer for bare-metal M-mode firmware on the
aRVern core.*

The rules it implements are those of [doc/traps_and_interrupts.md](../doc/traps_and_interrupts.md)
and [doc/software_guide.md](../doc/software_guide.md).

---

## Layout

```
sw/
├── include/
│   ├── arvern_csr.h      CSR read / write / set / clear, aRVern CSR numbers,
│   │                     mstatus / mie / mip / mcause / mncause / marv_estat fields,
│   │                     interrupt enable / save / restore, wfi
│   ├── arvern_cpu.h      build discovery: marchid, misa and marv_cfg decoded
│   └── arvern_irq.h      trap and interrupt API
└── src/
    ├── arvern_trap.S     trap entry (mtvec, direct mode) and RNMI entry (marv_nmvec)
    └── arvern_irq.c      handler tables and C dispatch
```

The peripheral drivers live with their IPs (`arvern-ips/<ip>/sw/`) and do not depend on
this library; an application combines them.

---

## Using it

```make
ARV_SW  = <path>/arvern/sw
SRCS   += $(ARV_SW)/src/arvern_irq.c $(ARV_SW)/src/arvern_trap.S
CFLAGS += -I$(ARV_SW)/include
```

```c
#include "arvern_irq.h"

static void on_timer(uint32_t cause) { /* re-arm the ACLINT compare ... */ }

int main(void)
{
    arv_irq_init();                    /* NMIE, MDT, mtvec, marv_nmvec, RNMI stack */
    arv_irq_attach(IRQ_M_TIMER, on_timer);
    arv_irq_enable(IRQ_M_TIMER);       /* mie.MTIE */
    arv_irq_global_enable();           /* mstatus.MIE */
    for (;;)
        arv_wfi();
}
```

Platform interrupts (`irq_platform_i[n]`) are causes `IRQ_PLATFORM(n)` = 16 + n. Their
pending bits are **latched**: a handler clears the request in the device first, then
calls `arv_irq_clear_pending(cause)`.

Build discovery: `arv_cpu_probe()` identifies the core (`marchid`) and decodes `misa` and
`marv_cfg` into the synthesized configuration (M level and multiplier / divider type, B
and C levels, S/U modes, counters, PMP entries, debug and triggers), so firmware adapts
to the build without probing CSRs and catching traps. A driver whose IP is built to match a core
option can take that option from here: in the reference SoCs, for instance, the ACLINT's
S-mode software interrupt is present when the core has S-mode (`su_mode`).

---

## Behaviour

- **Boot order.** Out of reset the hart cannot take a trap: `mnstatus.NMIE` must be set
  before `mstatush.MDT` is cleared. `arv_irq_init()` does both (`arv_irq_boot()`), and
  is safe to call when the startup code already has.
- **One entry, C dispatch.** The trap entry saves the caller-saved registers (RV32E or
  RV32I), passes `mcause`, `mepc`, `mtval` to the dispatcher and writes back the PC it
  returns. Interrupts resume at `mepc`; an exception handler returns the PC to resume at
  (`mepc + 4` or `+ 2` to skip the faulting instruction).
- **No nesting.** Handlers run with interrupts masked and `mstatush.MDT` set, as the
  hardware leaves them. A trap inside a handler is therefore a double trap, which the
  core diverts to the RNMI entry with the cause in `mncause[4:0]`: the default NMI
  handler records it in `arv_trap_last` and stops, a clean diagnostic instead of a
  corrupted `mepc`.
- **RNMIs.** The NMI entry runs on a private stack (held in `mnscratch`, 256 bytes by
  default, `ARV_NMI_STACK_WORDS`). The default handler resumes after a data-bus error
  (`mncause = 0x80000003`), recording `marv_epc` / `marv_eaddr` in `arv_trap_last` and
  clearing `marv_estat`; resumes after a pin NMI; and stops on a double-trap divert. An
  application that wants to replay a restartable access or report errors attaches its
  own with `arv_nmi_attach()`.
- **Unhandled traps.** An interrupt with no handler has its `mie` bit cleared (so it
  cannot storm) and is recorded; an exception with no handler is recorded and stops.
  `arv_trap_last` holds the last one for a debugger.
- **Vectored mode** is not used: the dispatch table costs a few instructions per
  interrupt and keeps one entry point.
